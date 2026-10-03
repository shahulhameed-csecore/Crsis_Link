import 'package:crsis_link_client/crsis_link_client.dart';
void main() async {
  final client = Client('https://crsis-link-api.onrender.com/');
  print('Fetching active SOS alerts...');
  final alerts = await client.sos.getActiveAlerts(0.0, 0.0);
  print('Found \${alerts.length} active alerts.');
  for (var alert in alerts) {
    print('Cancelling alert \${alert.id}...');
    try {
      await client.sos.resolveSOS(alert.id!, alert.deviceId);
      print('Resolved \${alert.id}');
    } catch (e) {
      print('Failed to resolve \${alert.id}: \$e');
    }
  }
  print('Done clearing database!');
}
