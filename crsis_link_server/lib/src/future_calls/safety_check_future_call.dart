import 'package:serverpod/serverpod.dart';
import '../generated/protocol.dart';

class SafetyCheckFutureCall extends FutureCall<SosAlert> {
  @override
  Future<void> invoke(Session session, SosAlert? alertPayload) async {
    if (alertPayload == null || alertPayload.id == null) return;
    
    final sosId = alertPayload.id!;

    final alert = await session.db.transaction((transaction) async {
      final targetAlert = await SosAlert.db.findById(session, sosId, transaction: transaction);
      
      // If it hasn't been completed, escalate it
      if (targetAlert != null && targetAlert.status == 'CLAIMED') {
        targetAlert.status = 'ESCALATED';
        return await SosAlert.db.updateRow(session, targetAlert, transaction: transaction);
      }
      return null;
    });

    if (alert != null) {
      final populatedAlert = await SosAlert.db.findById(
        session,
        alert.id!,
        include: SosAlert.include(userInfo: UserInfo.include()),
      );
      if (populatedAlert != null) {
        session.log('SOS $sosId has been ESCALATED due to no safety check-in.', level: LogLevel.warning);
        session.messages.postMessage('sos_alerts', populatedAlert);
      }
    }
  }
}
