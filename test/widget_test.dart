import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:crsis_link/main.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:crsis_link/core/auth/auth_manager.dart';
import 'package:crsis_link_client/crsis_link_client.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // Provide in-memory mock adapters for Hive & Secure Storage
    SharedPreferences.setMockInitialValues({'device_id': 'test_device'});
    
    const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (MethodCall methodCall) async {
      return null;
    });
    
    try {
      AuthManager.client = Client('http://localhost:8080/');
      AuthManager.deviceId = 'test_device';
      AuthManager.displayName = 'Test User';
    } catch (e) {
      // ignore init errors in test if any
    }
  });

  testWidgets('App smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const CrsisLinkApp());
    await tester.pump();

    // Verify that our app builds successfully and contains the text.
    expect(find.byType(MaterialApp), findsWidgets);
    expect(find.byKey(const ValueKey('sos_emergency_button')), findsWidgets);
  });
}
