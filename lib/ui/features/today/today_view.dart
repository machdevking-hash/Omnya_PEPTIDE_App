import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/compound_directory.dart';
import '../../../core/theme/omnya_colors.dart';
import '../../../core/theme/omnya_typography.dart';
import '../../../core/widgets/omnya_card.dart';
import '../../../core/widgets/omnya_controls.dart';
import '../../../core/widgets/omnya_pro_badge.dart';
import '../../../core/widgets/slide_page_route.dart';
import '../../../core/widgets/tactile_button.dart';
import '../../../data/models/daily_check_in.dart';
import '../../../data/models/dose_log.dart';
import '../../../data/repositories/protocol_repository.dart';
import '../../../data/services/native_service.dart';
import '../../../data/services/subscription_service.dart';
import '../../../domain/insights.dart';
import '../../../domain/schedule.dart';
import '../../core/omnya_header.dart';
import '../../core/settings_sheet.dart';
import '../../core/sync_status_indicator.dart';
import '../../onboarding/paywall_view.dart';
import '../photo_read/weekly_photo_view.dart';
import '../stack/compound_editor_sheet.dart';
import 'dose_logging.dart';

/// Spec page 2: one card for the dose, one for the check-in, one insight. Nothing else.
class TodayView extends StatelessWidget {
  const TodayView({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<ProtocolRepository>();
    final now = DateTime.now();
    // Cycle-aware insights are Pro (spec page 8).
    final insight = todayInsight(
      compounds: repo.compounds,
      logs: repo.doseLogs,
      checkIns: repo.checkIns,
      hasCycle: (repo.profile?.hasCycle ?? false) && context.watch<SubscriptionService>().isPro,
      now: now,
    );

    return RefreshIndicator(
      color: OmnyaColors.plum,
      backgroundColor: OmnyaColors.cream,
      onRefresh: repo.sync,
      child: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.only(bottom: 120),
        children: [
          OmnyaHeader(
            title: 'Today',
            showLogo: true,
            onLogoTap: () => showSettingsSheet(context),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Consumer<SubscriptionService>(
                  builder: (_, sub, _) => sub.isPro
                      ? const SizedBox.shrink()
                      : Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: OmnyaProBadge(
                            onTap: () => Navigator.push(context, SlidePageRoute(page: const PaywallView())),
                          ),
                        ),
                ),
                const SyncStatusIndicator(),
                const SizedBox(width: 8),
                OmnyaIconButton(
                  icon: HugeIcons.strokeRoundedSettings01,
                  tooltip: 'Settings',
                  onPressed: () => showSettingsSheet(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          _Entrance(
            index: 0,
            child: _DoseCard(repo: repo, now: now),
          ),
          const SizedBox(height: 16),
          _Entrance(
            index: 1,
            child: _CheckInCard(repo: repo, now: now),
          ),
          const SizedBox(height: 16),
          _Entrance(
            index: 2,
            child: _Padded(
              OmnyaCard(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(insight?.label ?? 'Your patterns', style: OmnyaTypography.tag(color: OmnyaColors.taupeDark)),
                    const SizedBox(height: 8),
                    Text(
                      insight?.text ?? 'Check in for a few days and your first pattern shows up here.',
                      style: OmnyaTypography.headline(
                        color: insight == null ? OmnyaColors.charcoalLight : OmnyaColors.charcoal,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Padded extends StatelessWidget {
  final Widget child;
  const _Padded(this.child);

  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.symmetric(horizontal: 14), child: child);
}

class _DoseCard extends StatelessWidget {
  final ProtocolRepository repo;
  final DateTime now;
  const _DoseCard({required this.repo, required this.now});

  @override
  Widget build(BuildContext context) {
    final compounds = repo.compounds;
    final logs = repo.doseLogs;
    final next = nextUp(compounds, logs);
    final unconfigured = compounds.where((c) => !c.isConfigured).firstOrNull;

    if (next == null) {
      final setUp = unconfigured;
      return _Padded(
        _PlumCard(
          label: setUp == null ? 'Your first dose' : 'Almost ready',
          title: setUp == null ? 'Nothing to log yet' : 'Set up ${CompoundDirectory.shortName(setUp.name)}',
          line: setUp == null
              ? 'Add what you take and your next dose shows up here.'
              : 'Add your dose and how often you take it.',
          action: TactileButton(
            label: setUp == null ? 'Add a compound' : 'Add dose and schedule',
            variant: TactileButtonVariant.onDark,
            width: double.infinity,
            onPressed: () => showCompoundEditor(context, compound: setUp),
          ),
        ),
      );
    }

    final dueIn = daysBetween(now, nextDueDay(next, logs));
    final loggedToday = logs.where((l) => sameDay(l.timestamp, now)).toList();

    // Nothing due until a later day and she already logged today: show the done state.
    if (dueIn > 0 && loggedToday.isNotEmpty) {
      final last = loggedToday.first;
      return _Padded(
        _PlumCard(
          label: 'Done for today',
          title: 'Logged ${CompoundDirectory.shortName(last.compoundName)}',
          line:
              'Next: ${CompoundDirectory.shortName(next.name)}, ${nextDoseLabel(next, logs)} · ${dueLine(next, logs, now)}',
          action: _UndoPill(log: last, repo: repo),
        ),
      );
    }

    return _Padded(
      _PlumCard(
        label: 'Next dose',
        chip: next.category.label,
        title: '${CompoundDirectory.shortName(next.name)}, ${nextDoseLabel(next, logs)}',
        line: dueLine(next, logs, now),
        action: TactileButton(
          label: 'Log it',
          variant: TactileButtonVariant.onDark,
          width: double.infinity,
          onPressed: () => logDoseWithFeedback(context, next),
        ),
      ),
    );
  }
}

class _PlumCard extends StatelessWidget {
  final String label;
  final String? chip;
  final String title;
  final String line;
  final Widget action;

  const _PlumCard({required this.label, this.chip, required this.title, required this.line, required this.action});

  @override
  Widget build(BuildContext context) {
    return OmnyaCard(
      color: OmnyaColors.plum,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label, style: OmnyaTypography.bodySmall(color: OmnyaColors.sandMuted)),
              ),
              if (chip != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: OmnyaColors.cream.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(OmnyaRadius.chip),
                  ),
                  child: Text(chip!, style: OmnyaTypography.tag(color: OmnyaColors.cream)),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Text(title, style: OmnyaTypography.displayMedium(color: OmnyaColors.cream)),
          const SizedBox(height: 6),
          Text(line, style: OmnyaTypography.bodyMedium(color: OmnyaColors.sandMuted)),
          const SizedBox(height: 22),
          action,
        ],
      ),
    );
  }
}

class _UndoPill extends StatelessWidget {
  final DoseLog log;
  final ProtocolRepository repo;
  const _UndoPill({required this.log, required this.repo});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      padding: const EdgeInsets.only(left: 18, right: 6),
      decoration: BoxDecoration(
        color: OmnyaColors.cream.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: OmnyaColors.cream.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              [formatDose(log.dose, log.unit), if (log.injectionSite.isNotEmpty) log.injectionSite].join(' · '),
              style: OmnyaTypography.label(color: OmnyaColors.cream),
            ),
          ),
          TextButton(
            onPressed: () {
              HapticFeedback.lightImpact();
              repo.undoDose(log);
            },
            style: TextButton.styleFrom(foregroundColor: OmnyaColors.sandMuted),
            child: Text(
              'Undo',
              style: OmnyaTypography.label(color: OmnyaColors.sandMuted, weight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _CheckInCard extends StatefulWidget {
  final ProtocolRepository repo;
  final DateTime now;
  const _CheckInCard({required this.repo, required this.now});

  @override
  State<_CheckInCard> createState() => _CheckInCardState();
}

class _CheckInCardState extends State<_CheckInCard> {
  int? _energy;
  int? _appetite;
  bool _periodStarted = false;
  bool _editing = false;
  bool _more = false;
  bool _healthEmpty = false;
  double? _weight;
  double? _waist;
  double? _sleep;
  int? _pain;
  int? _protein;
  int? _strength;
  final _notes = TextEditingController();
  Set<String> _effects = {};

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  static String _num(double? v) => v == null ? '' : v.toString().replaceFirst(RegExp(r'\.0$'), '');

  void _edit(DailyCheckIn existing) {
    setState(() {
      _editing = true;
      _energy = existing.energyLevel;
      _appetite = existing.appetiteLevel;
      _periodStarted = existing.periodStarted;
      _weight = existing.weightLbs;
      _waist = existing.waistIn;
      _sleep = existing.sleepHours;
      _notes.text = existing.notes;
      _pain = existing.pain;
      _protein = existing.proteinG;
      _strength = existing.strength;
      _effects = {...existing.sideEffects};
      _more =
          existing.waistIn != null ||
          existing.sleepHours != null ||
          existing.pain != null ||
          existing.proteinG != null ||
          existing.sideEffects.isNotEmpty ||
          existing.notes.isNotEmpty;
    });
  }

  Future<void> _fromHealth() async {
    final w = await NativeService.latestWeight();
    if (!mounted) return;
    // iOS doesn't tell apps whether reading was allowed, so "none found" covers a denial too.
    setState(() {
      _healthEmpty = w == null;
      if (w != null) _weight = double.parse(w.lbs.toStringAsFixed(1));
    });
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    HapticFeedback.mediumImpact();
    await widget.repo.saveCheckIn(
      energy: _energy!,
      appetite: _appetite!,
      weightLbs: _weight,
      waistIn: _waist,
      sleepHours: _sleep,
      pain: _pain,
      sideEffects: _effects.toList(),
      proteinG: _protein,
      strength: _strength,
      notes: _notes.text,
      periodStarted: _periodStarted,
    );
    if (mounted) setState(() => _editing = false);
  }

  @override
  Widget build(BuildContext context) {
    final today = widget.repo.checkInOn(widget.now);
    final hasCycle = widget.repo.profile?.hasCycle ?? false;
    final photoThisWeek = widget.repo.photoInWeekOf(widget.now) != null;
    // Strength is a weekly question: asked until it's answered this week, and on the day it was.
    final weekStart = weekStartOf(widget.now);
    final strengthThisWeek = widget.repo.checkIns.any(
      (c) => c.strength != null && !c.date.isBefore(weekStart) && c.id != today?.id,
    );

    return _Padded(
      OmnyaCard(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Daily check-in', style: OmnyaTypography.label(weight: FontWeight.w600)),
                ),
                if (today != null && !_editing)
                  GestureDetector(
                    onTap: () => _edit(today),
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Text(
                        'Edit',
                        style: OmnyaTypography.label(color: OmnyaColors.plum, weight: FontWeight.w600),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (today != null && !_editing)
              Text(
                [
                  if (today.energyLevel != null) 'Energy ${today.energyLevel}',
                  if (today.appetiteLevel != null) 'Appetite ${today.appetiteLevel}',
                  if (today.weightLbs != null) '${_num(today.weightLbs)} lb',
                  if (today.waistIn != null) '${_num(today.waistIn)} in waist',
                  if (today.sleepHours != null) '${_num(today.sleepHours)} h sleep',
                  if (today.pain != null) 'Pain ${today.pain}',
                  if (today.proteinG != null) '${today.proteinG} g protein',
                  if (today.strength != null) 'Strength ${today.strength}',
                  ...today.sideEffects,
                  if (today.periodStarted) 'Period started',
                ].join(' · '),
                style: OmnyaTypography.bodyLarge(color: OmnyaColors.charcoalMuted),
              )
            else ...[
              _Scale(label: 'Energy', value: _energy, onSelect: (v) => setState(() => _energy = v)),
              const SizedBox(height: 14),
              _Scale(label: 'Appetite', value: _appetite, onSelect: (v) => setState(() => _appetite = v)),
              if (!strengthThisWeek) ...[
                const SizedBox(height: 14),
                _Scale(label: 'Strength', value: _strength, onSelect: (v) => setState(() => _strength = v)),
                const SizedBox(height: 4),
                Text('Once a week: how strong did workouts feel?', style: OmnyaTypography.bodySmall()),
              ],
              const SizedBox(height: 16),
              OmnyaWheelField(
                label: 'Weight (optional)',
                value: _weight,
                min: 50,
                max: 800,
                step: 0.1,
                // Opens at her last weigh-in so the wheel starts close.
                start: widget.repo.checkIns.where((c) => c.weightLbs != null).firstOrNull?.weightLbs ?? 150,
                unit: 'lb',
                onChanged: (v) => setState(() => _weight = v),
              ),
              if (defaultTargetPlatform == TargetPlatform.iOS)
                TextButton(
                  onPressed: _fromHealth,
                  style: TextButton.styleFrom(padding: EdgeInsets.zero, foregroundColor: OmnyaColors.plum),
                  child: Text(
                    'Use my weight from Apple Health',
                    style: OmnyaTypography.label(color: OmnyaColors.plum, weight: FontWeight.w600),
                  ),
                ),
              if (_healthEmpty) Text('No weight found in Apple Health.', style: OmnyaTypography.bodySmall()),
              if (!_more)
                TextButton(
                  onPressed: () => setState(() => _more = true),
                  style: TextButton.styleFrom(padding: EdgeInsets.zero, foregroundColor: OmnyaColors.plum),
                  child: Text(
                    'Add waist, sleep, protein or notes',
                    style: OmnyaTypography.label(color: OmnyaColors.plum, weight: FontWeight.w600),
                  ),
                )
              else ...[
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: OmnyaWheelField(
                        label: 'Waist',
                        value: _waist,
                        min: 15,
                        max: 80,
                        step: 0.5,
                        start: widget.repo.checkIns.where((c) => c.waistIn != null).firstOrNull?.waistIn ?? 30,
                        unit: 'in',
                        onChanged: (v) => setState(() => _waist = v),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OmnyaWheelField(
                        label: 'Sleep',
                        value: _sleep,
                        min: 0,
                        max: 24,
                        step: 0.5,
                        start: 7,
                        unit: 'h',
                        onChanged: (v) => setState(() => _sleep = v),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OmnyaWheelField(
                        label: 'Pain',
                        value: _pain?.toDouble(),
                        min: 0,
                        max: 10,
                        hint: '0 to 10',
                        onChanged: (v) => setState(() => _pain = v?.round()),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                OmnyaWheelField(
                  label: 'Protein',
                  value: _protein?.toDouble(),
                  min: 0,
                  max: 300,
                  step: 5,
                  start: (widget.repo.profile?.proteinTargetG ?? 100).toDouble(),
                  unit: 'g',
                  onChanged: (v) => setState(() => _protein = v?.round()),
                ),
                const SizedBox(height: 14),
                Text('Anything else', style: OmnyaTypography.label(color: OmnyaColors.charcoalMuted)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final e in sideEffectOptions)
                      _Pill(
                        label: e,
                        selected: _effects.contains(e),
                        onTap: () => setState(() => _effects.contains(e) ? _effects.remove(e) : _effects.add(e)),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                OmnyaField(
                  label: 'Skin and hair notes',
                  controller: _notes,
                  hint: 'What you noticed',
                  maxLength: 500,
                  capitalization: TextCapitalization.sentences,
                ),
              ],
              if (hasCycle) ...[
                const SizedBox(height: 12),
                _Toggle(
                  label: 'My period started today',
                  value: _periodStarted,
                  onChanged: (v) => setState(() => _periodStarted = v),
                ),
              ],
              const SizedBox(height: 16),
              TactileButton(
                label: today == null ? 'Save check-in' : 'Save changes',
                width: double.infinity,
                onPressed: _energy != null && _appetite != null ? _save : null,
              ),
            ],
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 4),
            InkWell(
              onTap: () {
                HapticFeedback.lightImpact();
                Navigator.push(context, SlidePageRoute(page: const WeeklyPhotoView()));
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  children: [
                    const HugeIcon(icon: HugeIcons.strokeRoundedCameraSmile02, color: OmnyaColors.plum, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        photoThisWeek ? "This week's photo is in" : "Take this week's photo",
                        style: OmnyaTypography.label(weight: FontWeight.w600),
                      ),
                    ),
                    const HugeIcon(icon: HugeIcons.strokeRoundedArrowRight01, color: OmnyaColors.taupeDark, size: 18),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _Pill({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: selected ? OmnyaColors.plum : OmnyaColors.sandMuted,
            borderRadius: BorderRadius.circular(OmnyaRadius.chip),
          ),
          child: Text(
            label,
            style: OmnyaTypography.label(
              color: selected ? OmnyaColors.cream : OmnyaColors.charcoalMuted,
              weight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _Scale extends StatelessWidget {
  final String label;
  final int? value;
  final ValueChanged<int> onSelect;
  const _Scale({required this.label, required this.value, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 72, child: Text(label, style: OmnyaTypography.bodyMedium())),
        for (var v = 1; v <= 5; v++) ...[
          if (v > 1) const SizedBox(width: 6),
          Expanded(
            child: Semantics(
              button: true,
              selected: value == v,
              label: '$label $v of 5',
              excludeSemantics: true,
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  onSelect(v);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: value != null && v <= value! ? OmnyaColors.plum : OmnyaColors.sandMuted,
                    borderRadius: BorderRadius.circular(OmnyaRadius.chip),
                  ),
                  child: Text(
                    '$v',
                    style: OmnyaTypography.label(
                      color: value != null && v <= value! ? OmnyaColors.cream : OmnyaColors.charcoalMuted,
                      weight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _Toggle extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _Toggle({required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(label, style: OmnyaTypography.bodyMedium(color: OmnyaColors.charcoal)),
        ),
        Switch.adaptive(
          value: value,
          activeTrackColor: OmnyaColors.plum,
          onChanged: (v) {
            HapticFeedback.selectionClick();
            onChanged(v);
          },
        ),
      ],
    );
  }
}

/// One soft rise per card when Today first appears. Skipped with reduced motion.
class _Entrance extends StatelessWidget {
  final int index;
  final Widget child;
  const _Entrance({required this.index, required this.child});

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations) return child;
    final start = index * 0.12;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 700),
      curve: Interval(start, (start + 0.7).clamp(0, 1), curve: Curves.easeOutCubic),
      builder: (_, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, 14 * (1 - t)), child: child),
      ),
      child: child,
    );
  }
}
