import 'package:flutter_test/flutter_test.dart';
import 'package:mizdah/main.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  testWidgets('Splash screen shows Mizdah', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const ProviderScope(child: MizdahApp()));

    // Verify that the splash screen shows "Mizdah".
    expect(find.text('Mizdah'), findsOneWidget);
  });
}
