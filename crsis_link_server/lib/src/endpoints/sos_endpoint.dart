import 'dart:math';
import 'package:serverpod/serverpod.dart';
import '../generated/protocol.dart';

class DeviceLocationData {
  final double lat;
  final double lng;
  final DateTime lastUpdated;
  DeviceLocationData(this.lat, this.lng, this.lastUpdated);
}

/// Endpoint for handling SOS Alerts.
class SosEndpoint extends Endpoint {

  // In-memory location tracker for active devices
  static final Map<String, DeviceLocationData> _deviceLocations = {};
  
  // Track which deviceId corresponds to which StreamingSession to clean up on disconnect.
  static final Map<String, String> _sessionToDevice = {};

  // Track active targeted listeners per session to prevent duplicates
  static final Map<String, MessageCentralListenerCallback> _sessionListeners = {};

  @override
  Future<void> streamOpened(StreamingSession session) async {
    // We cannot get deviceId here without a message, but we can listen to general messages.
    // However, we will register listeners dynamically when they call updateLocation or via a setup message.
    final sessionId = session.sessionLogId.toString();
    final MessageCentralListenerCallback broadcastListener = (message) {
      sendStreamMessage(session, message);
    };
    session.messages.addListener('sos_broadcasts', broadcastListener);
    _sessionListeners["${sessionId}_broadcast"] = broadcastListener;
  }

  @override
  Future<void> streamClosed(StreamingSession session) async {
    final sessionId = session.sessionLogId.toString();
    
    final broadcastListener = _sessionListeners["${sessionId}_broadcast"];
    if (broadcastListener != null) {
      session.messages.removeListener('sos_broadcasts', broadcastListener);
      _sessionListeners.remove("${sessionId}_broadcast");
    }

    final deviceId = _sessionToDevice[sessionId];
    
    if (deviceId != null) {
      final listener = _sessionListeners[sessionId];
      if (listener != null) {
        session.messages.removeListener('sos_device_$deviceId', listener);
        _sessionListeners.remove(sessionId);
      }
      _deviceLocations.remove(deviceId);
      _sessionToDevice.remove(sessionId);
    }
  }

  @override
  Future<void> handleStreamMessage(StreamingSession session, SerializableModel message) async {
    if (message is Greeting) {
      final deviceId = message.message;
      final sessionId = session.sessionLogId.toString();
      
      _sessionToDevice[sessionId] = deviceId;
      
      if (!_sessionListeners.containsKey(sessionId)) {
        final MessageCentralListenerCallback listener = (msg) {
          sendStreamMessage(session, msg);
        };
        session.messages.addListener('sos_device_$deviceId', listener);
        _sessionListeners[sessionId] = listener;
      }
    }
  }

  /// Updates the device's last known location for targeted spatial broadcasting
  Future<void> updateLocation(Session session, String deviceId, double latitude, double longitude) async {
    _deviceLocations[deviceId] = DeviceLocationData(latitude, longitude, DateTime.now());
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
    print('SOS Triggered by $deviceId at $latitude, $longitude');
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
    print('Total devices in spatial cache: ${_deviceLocations.length}');
    // Spatial Filter: Broadcast ONLY to devices within 5000 meters
    for (final entry in _deviceLocations.entries.toList()) {
      final targetDeviceId = entry.key;
      final locationData = entry.value;

      if (DateTime.now().difference(locationData.lastUpdated).inMinutes > 5) {
        _deviceLocations.remove(targetDeviceId);
        continue;
      }
      
      // CRITICAL: Explicitly exclude the senderDeviceId from the list of eligible receivers
      if (targetDeviceId == deviceId) continue;
      
      final targetLat = locationData.lat;
      final targetLng = locationData.lng;
      
      final distance = _calculateDistance(latitude, longitude, targetLat, targetLng);
      print('Checking device $targetDeviceId - Distance: ${distance / 1000} km');
      
      if (distance <= 5000) { // 5km radius
        session.messages.postMessage('sos_device_$targetDeviceId', savedAlert);
        notifiedCount++;
      }
    }
    
    print('SOS broadcast successfully routed to $notifiedCount nearby devices.');
    
    return SosBroadcastResponse(
      alert: savedAlert,
      notifiedCount: notifiedCount,
    );
  }

  /// Retrieves all currently active SOS alerts within 5km.
  Future<List<SosAlert>> getActiveAlerts(Session session, double lat, double lng) async {
    final alerts = await SosAlert.db.find(
      session,
      where: (t) => t.isActive.equals(true),
    );
    
    return alerts.where((alert) {
      final distance = _calculateDistance(alert.latitude, alert.longitude, lat, lng);
      return distance <= 5000;
    }).toList();
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

    session.messages.postMessage('sos_broadcasts', SosResolvedEvent(sosId: sosId, deviceId: targetAlert.deviceId));
    return targetAlert;
  }
}

