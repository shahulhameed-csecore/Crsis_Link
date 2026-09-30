import 'package:flutter_test/flutter_test.dart';
import 'package:crsis_link/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const CrsisLinkApp());

    // Verify that our app builds successfully and contains the text.
    expect(find.text('WELCOME BACK, ALEX'), findsOneWidget);
  });
}
