import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/compound_directory.dart';
import '../../../core/theme/omnya_colors.dart';
import '../../../core/theme/omnya_typography.dart';
import '../../../core/widgets/omnya_card.dart';
import '../../../core/widgets/omnya_controls.dart';
import '../../../core/widgets/tactile_button.dart';
import '../../../data/models/compound.dart';
import '../../../data/models/dose_log.dart';
import '../../../data/repositories/protocol_repository.dart';
import '../../../data/services/subscription_service.dart';
import '../../../domain/schedule.dart';
import '../../core/omnya_header.dart';
import '../../onboarding/paywall_view.dart';
import 'calculator_modal.dart';
import 'compound_editor_sheet.dart';

/// Spec page 2: every compound as a card with runout, cadence and cost.
class StackView extends StatelessWidget {
  const StackView({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<ProtocolRepository>();
    final compounds = repo.compounds;
    final costed = compounds.where((c) => c.monthlyCost != null).toList();
    final now = DateTime.now();

    return ListView(
      padding: const EdgeInsets.only(bottom: 120),
      children: [
        OmnyaHeader(
          title: 'Stack',
          subtitle: 'Compounds and vials',
          trailing: OmnyaIconButton(
            icon: HugeIcons.strokeRoundedAdd01,
            tooltip: 'Add a compound',
            onPressed: () {
              final isPro = context.read<SubscriptionService>().isPro;
              if (!isPro && repo.compounds.length >= 2) {
                openPaywall(context);
              } else {
                showCompoundEditor(context);
              }
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (costed.isNotEmpty) ...[
                ProGate(
                  message: 'See your monthly spend with Pro',
                  child: _SpendCard(costed: costed),
                ),
                const SizedBox(height: 14),
              ],
              if (compounds.isEmpty)
                OmnyaCard(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
                  child: OmnyaEmptyState(
                    icon: const HugeIcon(icon: HugeIcons.strokeRoundedAmpoule, color: OmnyaColors.taupeDark, size: 28),
                    title: 'Nothing in your stack yet',
                    body: 'Add what you take to track doses, sites and when a vial runs out.',
                    action: TactileButton(label: 'Add a compound', onPressed: () => showCompoundEditor(context)),
                  ),
                )
              else
                for (final c in compounds) ...[
                  _CompoundCard(compound: c, logs: repo.doseLogs, now: now),
                  const SizedBox(height: 12),
                ],
              const SizedBox(height: 4),
              TactileButton(
                label: 'Mixing calculator',
                variant: TactileButtonVariant.outline,
                width: double.infinity,
                leading: const HugeIcon(icon: HugeIcons.strokeRoundedCalculator, color: OmnyaColors.plum, size: 18),
                onPressed: () => showCalculator(context),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SpendCard extends StatelessWidget {
  final List<Compound> costed;
  const _SpendCard({required this.costed});

  @override
  Widget build(BuildContext context) {
    final total = costed.fold<double>(0, (sum, c) => sum + c.monthlyCost!);
    final first = costed.first;
    return OmnyaCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Per month, at your schedule', style: OmnyaTypography.tag(color: OmnyaColors.taupeDark)),
                const SizedBox(height: 4),
                Text('\$${total.toStringAsFixed(0)}', style: OmnyaTypography.statNumber()),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '\$${first.costPerDose!.toStringAsFixed(2)}',
                style: OmnyaTypography.label(color: OmnyaColors.plum, weight: FontWeight.w600),
              ),
              Text('per ${CompoundDirectory.shortName(first.name)} dose', style: OmnyaTypography.bodySmall()),
            ],
          ),
        ],
      ),
    );
  }
}

class _CompoundCard extends StatelessWidget {
  final Compound compound;
  final List<DoseLog> logs;
  final DateTime now;
  const _CompoundCard({required this.compound, required this.logs, required this.now});

  String? get _badge {
    final c = compound;
    if (!c.isConfigured) return 'Needs dose and schedule';
    if (c.dosesLeft == 0) return 'Out of doses';
    final runout = runoutDay(c, logs);
    if (runout != null && daysBetween(now, runout) <= 6) return 'Runs out ${relativeDay(runout, now)}';
    if (c.dosesLeft != null) return '${c.dosesLeft} ${c.dosesLeft == 1 ? 'dose' : 'doses'} left';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final c = compound;
    final badge = _badge;
    final day = daysBetween(c.startDate, now) + 1;
    return OmnyaCard(
      onTap: () => showCompoundEditor(context, compound: c),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 9, right: 10),
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(color: c.category.tagColor, shape: BoxShape.circle),
                ),
              ),
              Expanded(child: Text(c.name, style: OmnyaTypography.headline())),
              if (badge != null)
                Container(
                  margin: const EdgeInsets.only(left: 8, top: 2),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: OmnyaColors.sand,
                    borderRadius: BorderRadius.circular(OmnyaRadius.chip),
                  ),
                  child: Text(badge, style: OmnyaTypography.bodySmall(color: OmnyaColors.plum)),
                ),
            ],
          ),
          if (c.nickname.isNotEmpty) ...[
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 18),
              child: Text(c.nickname, style: OmnyaTypography.bodyMedium()),
            ),
          ],
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.only(left: 18),
            child: Text(
              c.isConfigured
                  ? '${nextDoseLabel(c, logs)} · ${everyLabel(c.frequencyDays)}'
                        '${c.isInjected ? ' · next ${c.nextSite.toLowerCase()}' : ''}'
                        '${day > 0 ? ' · day $day' : ''}'
                  : 'Tap to add your dose and schedule',
              style: OmnyaTypography.bodySmall(color: OmnyaColors.taupeDark),
            ),
          ),
        ],
      ),
    );
  }
}
