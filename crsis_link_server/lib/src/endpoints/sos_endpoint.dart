import 'package:serverpod/serverpod.dart';
import 'package:serverpod_auth_server/serverpod_auth_server.dart';
import '../generated/protocol.dart';

/// Endpoint for handling SOS Alerts.
/// Only authenticated users can access these methods.
class SosEndpoint extends Endpoint {
  @override
  bool get requireLogin => true;

  @override
  Future<void> streamOpened(StreamingSession session) async {
    session.messages.addListener('sos_alerts', (message) {
      sendStreamMessage(session, message);
    });
  }

  /// Creates or updates an active SOS alert for the currently logged in user.
  Future<SosAlert> broadcastSos(Session session, double latitude, double longitude, String? message) async {
    // 1. Get the authenticated user ID
    final authInfo = session.authenticated;
    if (authInfo == null) {
      throw Exception('Unauthorized access.');
    }
    final userId = int.parse(authInfo.userIdentifier);

    // 2. Log the security event
    session.log('User $userId is broadcasting an SOS alert at ($latitude, $longitude).', level: LogLevel.warning);

    // 3. Deactivate any previous active alerts for this user
    final existingAlerts = await SosAlert.db.find(
      session,
      where: (t) => t.userInfoId.equals(userId) & t.isActive.equals(true),
    );
    for (var alert in existingAlerts) {
      alert.isActive = false;
      await SosAlert.db.updateRow(session, alert);
    }

    // 4. Create the new alert
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
    
    // Fetch with userInfo to broadcast complete data
    final populatedAlert = await SosAlert.db.findById(
      session,
      savedAlert.id!,
      include: SosAlert.include(userInfo: UserInfo.include()),
    );
    
    // Broadcast to all connected clients listening on this channel
    if (populatedAlert != null) {
      session.messages.postMessage('sos_alerts', populatedAlert);
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
    final authInfo = session.authenticated;
    if (authInfo == null) return false;
    
    final userId = int.parse(authInfo.userIdentifier);
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
    final authInfo = session.authenticated;
    if (authInfo == null) {
      throw Exception('Unauthorized access.');
    }
    final userId = int.parse(authInfo.userIdentifier);

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
    final authInfo = session.authenticated;
    if (authInfo == null) {
      throw Exception('Unauthorized access.');
    }
    final userId = int.parse(authInfo.userIdentifier);

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
