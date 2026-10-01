import 'dart:math';
import 'package:serverpod/serverpod.dart';
import 'package:serverpod_auth_server/serverpod_auth_server.dart';
import '../generated/protocol.dart';

/// Endpoint for handling SOS Alerts.
/// Only authenticated users can access these methods.
class SosEndpoint extends Endpoint {
  @override
  bool get requireLogin => true;

  // In-memory location tracker for active WebSocket sessions
  static final Map<int, Map<String, double>> _userLocations = {};

  @override
  Future<void> streamOpened(StreamingSession session) async {
    if (session.authenticated != null) {
      final userId = session.authenticated!.userId;
      // Listen ONLY to this user's targeted SOS channel
      session.messages.addListener('sos_user_$userId', (message) {
        sendStreamMessage(session, message);
      });
      // Also listen to global cancellations or completions if needed, but let's keep it simple
    }
  }

  @override
  Future<void> streamClosed(StreamingSession session) async {
    if (session.authenticated != null) {
      _userLocations.remove(session.authenticated!.userId);
    }
  }

  /// Updates the user's last known location for targeted spatial broadcasting
  Future<void> updateLocation(Session session, double latitude, double longitude) async {
    if (session.authenticated == null) return;
    _userLocations[session.authenticated!.userId] = {'lat': latitude, 'lng': longitude};
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

  /// Creates or updates an active SOS alert for the currently logged in user.
  Future<SosAlert> broadcastSos(Session session, double latitude, double longitude, String? message) async {
    if (session.authenticated == null) {
      throw Exception('Unauthorized access.');
    }
    final userId = session.authenticated!.userId;
    session.log('User $userId is broadcasting an SOS alert at ($latitude, $longitude).', level: LogLevel.warning);

    final existingAlerts = await SosAlert.db.find(
      session,
      where: (t) => t.userInfoId.equals(userId) & t.isActive.equals(true),
    );
    for (var alert in existingAlerts) {
      alert.isActive = false;
      await SosAlert.db.updateRow(session, alert);
    }

    final newAlert = SosAlert(
      userInfoId: userId,
      latitude: latitude,
      longitude: longitude,
      timestamp: DateTime.now().toUtc(),
      message: message,
      isActive: true,
      status: 'OPEN',
    );

    final savedAlert = await SosAlert.db.insertRow(session, newAlert);
    
    final populatedAlert = await SosAlert.db.findById(
      session,
      savedAlert.id!,
      include: SosAlert.include(userInfo: UserInfo.include()),
    );
    
    if (populatedAlert != null) {
      // Spatial Filter: Broadcast ONLY to users within 5000 meters
      for (final entry in _userLocations.entries) {
        final targetUserId = entry.key;
        final targetLat = entry.value['lat']!;
        final targetLng = entry.value['lng']!;
        
        final distance = _calculateDistance(latitude, longitude, targetLat, targetLng);
        
        if (distance <= 5000) { // 5km radius
          session.messages.postMessage('sos_user_$targetUserId', populatedAlert);
        }
      }
    }
    
    return savedAlert;
  }

  /// Retrieves all currently active SOS alerts.
  Future<List<SosAlert>> getActiveAlerts(Session session) async {
    // Implicitly protected by requireLogin = true

    final alerts = await SosAlert.db.find(
      session,
      where: (t) => t.isActive.equals(true),
      include: SosAlert.include(
        userInfo: UserInfo.include(),
      ),
    );

    return alerts;
  }

  /// Cancels the active SOS alert for the logged in user.
  Future<bool> cancelSos(Session session) async {
    if (session.authenticated == null) return false;
    
    final userId = session.authenticated!.userId;
    session.log('User $userId is cancelling their SOS alert.', level: LogLevel.info);

    final existingAlerts = await SosAlert.db.find(
      session,
      where: (t) => t.userInfoId.equals(userId) & t.isActive.equals(true),
    );
    
    bool canceledAny = false;
    for (var alert in existingAlerts) {
      alert.isActive = false;
      await SosAlert.db.updateRow(session, alert);
      
      final populatedAlert = await SosAlert.db.findById(
        session,
        alert.id!,
        include: SosAlert.include(userInfo: UserInfo.include()),
      );
      if (populatedAlert != null) {
        session.messages.postMessage('sos_alerts', populatedAlert);
      }
      
      canceledAny = true;
    }
    return canceledAny;
  }

  /// Claims an active SOS alert
  Future<SosAlert> claimRescue(Session session, int sosId) async {
    if (session.authenticated == null) {
      throw Exception('Unauthorized access.');
    }
    final userId = session.authenticated!.userId;

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
      targetAlert.volunteerId = userId;
      return await SosAlert.db.updateRow(session, targetAlert, transaction: transaction);
    });

    final populatedAlert = await SosAlert.db.findById(
      session,
      alert.id!,
      include: SosAlert.include(userInfo: UserInfo.include()),
    );
    
    if (populatedAlert != null) {
      session.messages.postMessage('sos_alerts', populatedAlert);
      
      // Schedule safety check for 30 seconds (development mode)
      await session.serverpod.futureCallWithDelay(
        'safetyCheck',
        populatedAlert,
        const Duration(seconds: 30),
      );
    }
    return populatedAlert!;
  }

  /// Completes an active SOS alert (called when rescuer is safe)
  Future<SosAlert> completeRescue(Session session, int sosId) async {
    if (session.authenticated == null) {
      throw Exception('Unauthorized access.');
    }
    final userId = session.authenticated!.userId;

    final targetAlert = await SosAlert.db.findById(session, sosId);
    if (targetAlert == null) {
      throw Exception('SOS alert not found.');
    }
    if (targetAlert.volunteerId != userId) {
      throw Exception('Only the assigned volunteer can complete this rescue.');
    }

    targetAlert.status = 'COMPLETED';
    targetAlert.isActive = false;
    await SosAlert.db.updateRow(session, targetAlert);

    final populatedAlert = await SosAlert.db.findById(
      session,
      targetAlert.id!,
      include: SosAlert.include(userInfo: UserInfo.include()),
    );
    
    if (populatedAlert != null) {
      session.messages.postMessage('sos_alerts', populatedAlert);
    }
    return populatedAlert!;
  }
}
