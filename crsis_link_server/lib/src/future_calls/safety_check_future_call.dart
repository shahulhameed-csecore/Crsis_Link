import 'package:serverpod/serverpod.dart';
import 'package:serverpod_auth_server/serverpod_auth_server.dart';
import '../generated/protocol.dart';

class SafetyCheckFutureCall extends FutureCall<SosAlert> {
  @override
  Future<void> invoke(Session session, SosAlert? alertPayload) async {
    if (alertPayload == null || alertPayload.id == null) return;
    
    final sosId = alertPayload.id!;

    final alert = await session.db.transaction((transaction) async {
      final targetAlert = await SosAlert.db.findById(session, sosId, transaction: transaction);
      
      // If the claim was abandoned, release it back to OPEN for a new rescuer
      if (targetAlert != null && targetAlert.status == 'CLAIMED') {
        targetAlert.status = 'OPEN';
        targetAlert.volunteerDeviceId = null;
        targetAlert.verificationPin = null;
        targetAlert.isRescuerVerified = false;
        return await SosAlert.db.updateRow(session, targetAlert, transaction: transaction);
      }
      return null;
    });

    if (alert != null) {
      session.log('SOS $sosId claim timed out and was re-opened for new rescuers.', level: LogLevel.warning);
      session.messages.postMessage('sos_broadcasts', alert);
    }
  }
}
