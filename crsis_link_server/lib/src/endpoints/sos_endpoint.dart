import 'dart:math';
import 'package:serverpod/serverpod.dart';
import '../generated/protocol.dart';

/// Endpoint for handling SOS Alerts.
class SosEndpoint extends Endpoint {

  // In-memory location tracker for active devices
  static final Map<String, Map<String, double>> _deviceLocations = {};
  
  // Track which deviceId corresponds to which StreamingSession to clean up on disconnect.
  static final Map<String, String> _sessionToDevice = {};

  @override
  Future<void> streamOpened(StreamingSession session) async {
    // We cannot get deviceId here without a message, but we can listen to general messages.
    // However, we will register listeners dynamically when they call updateLocation or via a setup message.
    session.messages.addListener('sos_broadcasts', (message) {
      sendStreamMessage(session, message);
    });
  }

  @override
  Future<void> streamClosed(StreamingSession session) async {
    final deviceId = _sessionToDevice[session.sessionLogId.toString()];
    if (deviceId != null) {
      _deviceLocations.remove(deviceId);
      _sessionToDevice.remove(session.sessionLogId.toString());
    }
  }

  /// Updates the device's last known location for targeted spatial broadcasting
  Future<void> updateLocation(Session session, String deviceId, double latitude, double longitude) async {
    _deviceLocations[deviceId] = {'lat': latitude, 'lng': longitude};
    if (session is StreamingSession) {
       _sessionToDevice[session.sessionLogId.toString()] = deviceId;
       
       // Subscribe this session to targeted messages for this device
       session.messages.addListener('sos_device_$deviceId', (message) {
          sendStreamMessage(session, message);
       });
    }
  }

  // Haversine distance formula (returns meters)
  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371e3; // Earth radius in meters
    final phi1 = lat1 * (3.141592653589793 / 180.0);
    final phi2 = lat2 * (3.141592653589793 / 180.0);
    final deltaPhi = (lat2 - lat1) * (3.141592653589793 / 180.0);
    final deltaLambda = (lon2 - lon1) * (3.141592653589793 / 180.0);

    final a = (sin(deltaPhi / 2) * sin(deltaPhi / 2)) +
              (cos(phi1) * cos(phi2) * sin(deltaLambda / 2) * sin(deltaLambda / 2));
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }

  /// Creates or updates an active SOS alert for the given device.
  Future<SosBroadcastResponse> broadcastSos(Session session, String deviceId, String senderName, double latitude, double longitude, String? message, String? audioUrl) async {
    session.log('Device $deviceId is broadcasting an SOS alert at ($latitude, $longitude).', level: LogLevel.warning);

    final existingAlerts = await SosAlert.db.find(
      session,
      where: (t) => t.deviceId.equals(deviceId) & t.isActive.equals(true),
    );
    for (var alert in existingAlerts) {
      alert.isActive = false;
      await SosAlert.db.updateRow(session, alert);
    }

    final newAlert = SosAlert(
      deviceId: deviceId,
      latitude: latitude,
      longitude: longitude,
      timestamp: DateTime.now().toUtc(),
      message: message,
      isActive: true,
      status: 'OPEN',
      senderName: senderName,
      audioUrl: audioUrl,
    );

    final savedAlert = await SosAlert.db.insertRow(session, newAlert);
    
    int notifiedCount = 0;
    // Spatial Filter: Broadcast ONLY to devices within 5000 meters
    for (final entry in _deviceLocations.entries) {
      final targetDeviceId = entry.key;
      
      // CRITICAL: Explicitly exclude the senderDeviceId from the list of eligible receivers
      if (targetDeviceId == deviceId) continue;
      
      final targetLat = entry.value['lat']!;
      final targetLng = entry.value['lng']!;
      
      final distance = _calculateDistance(latitude, longitude, targetLat, targetLng);
      
      if (distance <= 5000) { // 5km radius
        session.messages.postMessage('sos_device_$targetDeviceId', savedAlert);
        notifiedCount++;
      }
    }
    
    return SosBroadcastResponse(
      alert: savedAlert,
      notifiedCount: notifiedCount,
    );
  }

  /// Retrieves all currently active SOS alerts.
  Future<List<SosAlert>> getActiveAlerts(Session session) async {
    final alerts = await SosAlert.db.find(
      session,
      where: (t) => t.isActive.equals(true),
    );
    return alerts;
  }

  /// Cancels the active SOS alert for the device.
  Future<bool> cancelSos(Session session, String deviceId) async {
    session.log('Device $deviceId is cancelling their SOS alert.', level: LogLevel.info);

    final existingAlerts = await SosAlert.db.find(
      session,
      where: (t) => t.deviceId.equals(deviceId) & t.isActive.equals(true),
    );
    
    bool canceledAny = false;
    for (var alert in existingAlerts) {
      alert.isActive = false;
      alert.status = 'CANCELLED';
      await SosAlert.db.updateRow(session, alert);
      
      // Notify nearby devices about cancellation if needed.
      session.messages.postMessage('sos_broadcasts', alert);
      canceledAny = true;
    }
    return canceledAny;
  }
  
  /// Resolves an active SOS alert
  Future<bool> resolveSOS(Session session, int sosId, String deviceId) async {
    final alert = await SosAlert.db.findById(session, sosId);
    if (alert == null || alert.deviceId != deviceId) {
      return false;
    }
    
    alert.isActive = false;
    alert.status = 'RESOLVED';
    await SosAlert.db.updateRow(session, alert);
    
    // Broadcast the resolved event
    session.messages.postMessage('sos_broadcasts', SosResolvedEvent(sosId: sosId, deviceId: deviceId));
    
    return true;
  }

  /// Claims an active SOS alert
  Future<SosAlert> claimRescue(Session session, String volunteerDeviceId, String volunteerName, int sosId) async {
    // Run inside a transaction to prevent race conditions
    final alert = await session.db.transaction((transaction) async {
      final targetAlert = await SosAlert.db.findById(session, sosId, transaction: transaction);
      if (targetAlert == null) {
        throw Exception('SOS alert not found.');
      }
      if (targetAlert.status != 'OPEN') {
        throw Exception('SOS alert is already claimed or resolved.');
      }

      targetAlert.status = 'CLAIMED';
      targetAlert.volunteerDeviceId = volunteerDeviceId;
      return await SosAlert.db.updateRow(session, targetAlert, transaction: transaction);
    });

    session.messages.postMessage('sos_broadcasts', alert);
    
    // Broadcast the RescueAcceptedEvent to all connected devices for the Alerts ledger
    session.messages.postMessage(
      'sos_broadcasts', 
      RescueAcceptedEvent(victimDeviceId: alert.deviceId, volunteerName: volunteerName, volunteerDeviceId: volunteerDeviceId)
    );
    
    return alert;
  }

  /// Completes an active SOS alert (called when rescuer is safe)
  Future<SosAlert> completeRescue(Session session, String volunteerDeviceId, int sosId) async {
    final targetAlert = await SosAlert.db.findById(session, sosId);
    if (targetAlert == null) {
      throw Exception('SOS alert not found.');
    }
    if (targetAlert.volunteerDeviceId != volunteerDeviceId) {
      throw Exception('Only the assigned volunteer can complete this rescue.');
    }

    targetAlert.status = 'COMPLETED';
    targetAlert.isActive = false;
    await SosAlert.db.updateRow(session, targetAlert);

    session.messages.postMessage('sos_broadcasts', targetAlert);
    return targetAlert;
  }
}

