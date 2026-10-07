// ignore_for_file: avoid_print
import 'package:crsis_link_client/crsis_link_client.dart';

void main() async {
  final client = Client('https://crsis-link-api.onrender.com/');
  print('Connecting to live server to fetch active alerts...');
  
  try {
    print('Attempting to nuke all test data...');
    // Replace DEV_ADMIN_SECRET with the actual secret from your config if needed
    final success = await client.sos.nukeAllTestData(devSecret: 'DEV_ADMIN_SECRET');
    if (success) {
      print('All stale pins have been successfully cleared from the live server!');
    } else {
      print('Failed to clear pins. Unauthorized.');
    }
    
    print('All stale pins have been successfully cleared from the live server!');
  } catch (e) {
    print('Error: $e');
  } finally {
    client.close();
  }
}
