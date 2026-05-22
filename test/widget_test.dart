// LVTField basic smoke test
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lvtfield/app.dart';

void main() {
  testWidgets('LVTField app smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(
      const ProviderScope(
        child: LVTFieldApp(),
      ),
    );

    // Verify the app name is displayed
    expect(find.text('LVTField'), findsOneWidget);

    // Verify the tagline is displayed
    expect(find.text('Khảo sát rừng di động'), findsOneWidget);

    // Verify FAB exists for creating new project
    expect(find.text('Dự án mới'), findsOneWidget);
  });
}
