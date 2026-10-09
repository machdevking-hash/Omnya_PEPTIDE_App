import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:omnya/core/theme/omnya_theme.dart';
import 'package:omnya/core/widgets/omnya_controls.dart';
import 'package:omnya/core/widgets/tactile_button.dart';
import 'package:omnya/data/repositories/protocol_repository.dart';
import 'package:omnya/data/services/subscription_service.dart';
import 'package:omnya/ui/navigation/main_shell.dart';
import 'package:omnya/ui/onboarding/onboarding_quiz_view.dart';
import 'fakes.dart';

void main() {
  late ProtocolRepository repo;

  setUp(() async {
    repo = await makeRepo(FakeCloud());
    await settle();
  });

  Future<void> pumpApp(WidgetTester tester, Widget home) async {
    tester.view.physicalSize = const Size(1170, 2532); // iPhone-sized, 390 x 844 pt
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: repo),
          ChangeNotifierProvider(create: (_) => SubscriptionService(storage: repo.storage)),
        ],
        child: MaterialApp(theme: OmnyaTheme.lightTheme, home: home),
      ),
    );
    await tester.pumpAndSettle();
  }

  // Lets toasts and the sync debounce run out so no timers outlive the test.
  Future<void> drain(WidgetTester tester) => tester.pump(const Duration(seconds: 5));

  VoidCallback? onPressed(WidgetTester tester, String label) =>
      tester.widget<TactileButton>(find.widgetWithText(TactileButton, label)).onPressed;

  testWidgets('first launch: every tab shows an honest empty state, nothing seeded', (tester) async {
    await pumpApp(tester, const MainShell());
    expect(find.text('Nothing to log yet'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Check in for a few days and your first pattern shows up here.'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Check in for a few days and your first pattern shows up here.'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Progress'));
    await tester.pumpAndSettle();
    expect(find.text('Before and after starts here'), findsOneWidget);
    expect(find.text('Add your weight in the daily check-in to see your trend here.'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Stack'));
    await tester.pumpAndSettle();
    expect(find.text('Nothing in your stack yet'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Circle'));
    await tester.pumpAndSettle();
    expect(find.text('Keep each other going'), findsOneWidget);
    expect(find.textContaining('Mia'), findsNothing);
    await drain(tester);
  });

  testWidgets('onboarding: nothing is pre-selected and Continue waits for an answer', (tester) async {
    await pumpApp(tester, const OnboardingQuizView());
    expect(onPressed(tester, 'Continue'), isNull);
    await tester.tap(find.text('Glow'));
    await tester.pump();
    expect(onPressed(tester, 'Continue'), isNotNull);

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Not sure yet'));
    await tester.pump();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('First month'));
    await tester.pump();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('No'), findsOneWidget, reason: 'spec lists yes, no, irregular, on birth control');
    await drain(tester);
  });

  testWidgets('add a compound, log it, see the first-dose moment, then undo', (tester) async {
    await pumpApp(tester, const MainShell());

    await tester.tap(find.text('Add a compound'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Retatrutide'));
    await tester.enterText(
      find.descendant(of: find.widgetWithText(OmnyaField, 'Dose'), matching: find.byType(TextField)),
      '2',
    );
    await tester.ensureVisible(find.text('Weekly'));
    await tester.tap(find.text('Weekly'));
    await tester.ensureVisible(find.text('Add to stack'));
    await tester.tap(find.text('Add to stack'));
    await tester.pumpAndSettle();

    expect(find.text('Reta, 2 mg'), findsOneWidget);
    expect(find.text('Left thigh · due today'), findsOneWidget);

    await tester.tap(find.text('Log it'));
    await tester.pumpAndSettle();
    expect(find.text('Day 1.'), findsOneWidget);
    await tester.tap(find.text('Done'));
    // Not pumpAndSettle: that would wait out the toast's countdown and it would be gone.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('Logged Reta, 2 mg'), findsOneWidget);
    expect(repo.doseLogs.length, 1);
    expect(repo.compounds.single.nextSite, 'Right thigh');

    await tester.tap(find.text('Undo').first);
    await tester.pump(const Duration(milliseconds: 600));
    expect(repo.doseLogs, isEmpty);
    expect(repo.compounds.single.nextSite, 'Left thigh');
    expect(find.text('Log it'), findsOneWidget);
    await drain(tester);
  });

  testWidgets('daily check-in saves and shows a summary', (tester) async {
    await pumpApp(tester, const MainShell());
    expect(onPressed(tester, 'Save check-in'), isNull);
    await tester.tap(find.bySemanticsLabel('Energy 4 of 5'));
    await tester.tap(find.bySemanticsLabel('Appetite 2 of 5'));
    await tester.pump();
    // Clear of the floating tab bar, which sits over the bottom of the list.
    await tester.ensureVisible(find.text('Save check-in'));
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -200));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save check-in'));
    await tester.pumpAndSettle();
    expect(find.text('Energy 4 · Appetite 2'), findsOneWidget);
    expect(repo.checkIns.single.energyLevel, 4);
    await drain(tester);
  });

  testWidgets('navigation tab bar renders all 5 icons with SVG pictures and labels', (tester) async {
    await pumpApp(tester, const MainShell());

    // On non-iOS-26 (fallback), 5 SvgPicture instances render each navigation asset cleanly.
    expect(find.byWidgetPredicate((w) => w is SvgPicture && w.bytesLoader is SvgAssetLoader), findsNWidgets(5));
    expect(find.bySemanticsLabel('Progress'), findsOneWidget);
    expect(find.bySemanticsLabel('Stack'), findsOneWidget);
    expect(find.bySemanticsLabel('Circle'), findsOneWidget);
    expect(find.bySemanticsLabel('Log a dose'), findsOneWidget);
    expect(find.ancestor(of: find.byType(SvgPicture).first, matching: find.bySemanticsLabel('Today')), findsOneWidget);
    await drain(tester);
  });
}
