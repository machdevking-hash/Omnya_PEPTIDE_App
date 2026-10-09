import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/omnya_colors.dart';
import '../../../core/theme/omnya_typography.dart';
import '../../../core/widgets/omnya_card.dart';
import '../../../core/widgets/omnya_controls.dart';
import '../../../data/repositories/protocol_repository.dart';
import '../../../domain/outcomes.dart';
import '../../onboarding/paywall_view.dart';

/// Spec: Sunday. What changed, what's due, what to watch.
class WeeklyReportView extends StatelessWidget {
  const WeeklyReportView({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<ProtocolRepository>();
    final report = weeklyReport(
      compounds: repo.compounds,
      logs: repo.doseLogs,
      checkIns: repo.checkIns,
      hasCycle: repo.profile?.hasCycle ?? false,
      now: DateTime.now(),
    );

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 40),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: OmnyaIconButton(
                icon: HugeIcons.strokeRoundedArrowLeft01,
                tooltip: 'Back',
                onPressed: () => Navigator.pop(context),
              ),
            ),
            const SizedBox(height: 12),
            Text('Your week', style: OmnyaTypography.displayMedium()),
            const SizedBox(height: 6),
            Text('The last 7 days, from your logs.', style: OmnyaTypography.bodyMedium()),
            const SizedBox(height: 24),
            if (report.isEmpty)
              const OmnyaCard(
                padding: EdgeInsets.symmetric(horizontal: 24, vertical: 36),
                child: OmnyaEmptyState(
                  icon: HugeIcon(icon: HugeIcons.strokeRoundedCalendar03, color: OmnyaColors.taupeDark, size: 28),
                  title: 'Nothing to report yet',
                  body: 'Log doses and check in this week. Your report fills in from there.',
                ),
              )
            else ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(report.headline, style: OmnyaTypography.headline()),
              ),
              ProGate(
                message: 'See your full week with Pro.',
                child: Column(
                  children: [
                    _Section('What changed', report.changed, empty: 'Check in on more days to compare weeks.'),
                    _Section('Coming up', report.due, empty: 'Nothing due in the next 7 days.'),
                    _Section('To watch', report.watch, empty: 'Nothing logged to watch this week.'),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<String> lines;
  final String empty;
  const _Section(this.title, this.lines, {required this.empty});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: OmnyaCard(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: OmnyaTypography.label(weight: FontWeight.w600)),
            const SizedBox(height: 10),
            if (lines.isEmpty)
              Text(empty, style: OmnyaTypography.bodyMedium())
            else
              for (final l in lines)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(l, style: OmnyaTypography.bodyLarge(color: OmnyaColors.charcoal)),
                ),
          ],
        ),
      ),
    );
  }
}
