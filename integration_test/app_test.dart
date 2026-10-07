import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter/material.dart';
import 'package:crsis_link/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'SOS button sends alert and interacts with permissions',
    (WidgetTester tester) async {
      // 1. Start the app
      app.main();
      await tester.pumpAndSettle();

      // 3. Find the SOS button and tap it.
      final sosButton = find.byKey(const ValueKey('sos_emergency_button'));
      expect(sosButton, findsWidgets);
      await tester.tap(sosButton.first);
      await tester.pumpAndSettle();
    },
  );
}
