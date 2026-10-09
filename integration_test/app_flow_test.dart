import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:peptide_app/core/theme/omnya_theme.dart';
import 'package:peptide_app/core/widgets/omnya_controls.dart';
import 'package:peptide_app/data/services/subscription_service.dart';
import 'package:peptide_app/ui/navigation/main_shell.dart';
import '../test/fakes.dart';

/// Runs on a device against an in-memory cloud, so it never writes to production.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('add a compound, log it, visit every tab', (tester) async {
    final repo = await makeRepo(FakeCloud());
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: repo),
          ChangeNotifierProvider(create: (_) => SubscriptionService(storage: repo.storage)),
        ],
        child: MaterialApp(theme: OmnyaTheme.lightTheme, home: const MainShell()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Nothing to log yet'), findsOneWidget);

    await tester.tap(find.text('Add a compound'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('GHK-Cu'));
    await tester.enterText(
      find.descendant(of: find.widgetWithText(OmnyaField, 'Dose'), matching: find.byType(TextField)),
      '1.5',
    );
    await tester.ensureVisible(find.text('Daily'));
    await tester.tap(find.text('Daily'));
    await tester.ensureVisible(find.text('Add to stack'));
    await tester.tap(find.text('Add to stack'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Log it'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(repo.doseLogs.length, 1);

    for (final tab in ['Progress', 'Stack', 'Circle', 'Today']) {
      await tester.tap(find.text(tab).last);
      await tester.pumpAndSettle();
    }
    expect(find.text('Done for today'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });
}
