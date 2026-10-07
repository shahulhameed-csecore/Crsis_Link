// ignore_for_file: avoid_print
import 'package:crsis_link_client/crsis_link_client.dart';
void main() async {
  final client = Client('https://crsis-link-api.onrender.com/');
  print('Nuking all test data...');
  try {
    await client.sos.nukeAllTestData(devSecret: 'YOUR_DEV_SECRET_HERE');
    print('Done clearing database completely!');
  } catch (e) {
    print('Failed to nuke database: \$e');
  }
}
