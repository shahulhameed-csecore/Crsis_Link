import 'package:serverpod/serverpod.dart';
import 'dart:async';
import '../generated/protocol.dart';

class SafetyCheckFutureCall extends FutureCall<SosAlert> {
  @override
  Future<void> invoke(Session session, SosAlert? object) async {
    if (object == null || object.id == null) return;
    
    final sosId = object.id!;

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
      try {
        await session.messages.postMessage('sos_broadcasts', alert);
      } catch (e) {
        session.log('Failed to broadcast timeout event: $e', level: LogLevel.error);
      }
    }
  }
}
