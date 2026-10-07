// ignore_for_file: avoid_print
import 'package:crsis_link_client/crsis_link_client.dart';

void main() async {
  final client = Client('https://crsis-link-api.onrender.com/');
  print('Connecting to live server to fetch active alerts...');
  
  try {
    final alerts = await client.sos.getActiveAlerts(0.0, 0.0);
    print('Found ${alerts.length} active pins.');
    
    for (var alert in alerts) {
      print('Resolving pin ID: ${alert.clientAlertId} from device: ${alert.deviceId}');
      await client.sos.resolveSOS(alert.clientAlertId, alert.deviceId);
    }
    
    print('All stale pins have been successfully cleared from the live server!');
  } catch (e) {
    print('Error: $e');
  } finally {
    client.close();
  }
}
