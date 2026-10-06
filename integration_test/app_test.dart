import 'package:patrol/patrol.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crsis_link/main.dart' as app;

void main() {
  patrolTest(
    'SOS button sends alert and interacts with permissions',
    ($) async {
      // 1. Start the app
      app.main();
      await $.pumpAndSettle();

      // 2. Interact with native OS permission dialogs!
      // This accepts the location/bluetooth prompts automatically
      if (await $.native.isPermissionDialogVisible()) {
        await $.native.grantPermissionWhenInUse();
      }

      // 3. Find the SOS button and tap it.
      // We assume your SOS button has a Key('sosButton') or text 'SOS'
      // Replace this with the actual text or key of your SOS button if different
      await $(#sosButton).tap();
      
      // 4. Verify the alert showed up
      // Replace with actual text that appears when SOS is sent
      expect($('SOS Alert Broadcasted'), findsOneWidget);
    },
  );
}
