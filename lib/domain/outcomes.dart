import 'package:intl/intl.dart';
import '../core/constants/compound_directory.dart';
import '../data/models/compound.dart';
import '../data/models/daily_check_in.dart';
import '../data/models/dose_log.dart';
import '../data/models/progress_photo.dart';
import 'insights.dart';
import 'schedule.dart';

// Everything here reads her own logs back to her in plain English.
// Nothing recommends a dose or a change to her protocol.

/// The outcome engine wakes up on day 14 of logging.
const outcomeStartDay = 14;

class Metric {
  final String name;
  final String unit;
  final double? Function(DailyCheckIn) read;

  /// Smaller changes are noise, so they aren't reported.
  final double minChange;
  const Metric(this.name, this.unit, this.read, this.minChange);
}

final metrics = <Metric>[
  Metric('weight', 'lb', (c) => c.weightLbs, 0.5),
  Metric('waist', 'in', (c) => c.waistIn, 0.25),
  Metric('energy', '', (c) => c.energyLevel?.toDouble(), 0.5),
  Metric('appetite', '', (c) => c.appetiteLevel?.toDouble(), 0.5),
  Metric('sleep', 'h', (c) => c.sleepHours, 0.5),
  Metric('pain', '', (c) => c.pain?.toDouble(), 1),
  Metric('protein', 'g', (c) => c.proteinG?.toDouble(), 10),
];

/// Average of [m] over check-ins from [from] up to, not including, [to].
double? averageBetween(List<DailyCheckIn> checkIns, Metric m, DateTime from, DateTime to) {
  final values = [
    for (final c in checkIns)
      if (!c.date.isBefore(from) && c.date.isBefore(to)) m.read(c),
  ].whereType<double>().toList();
  if (values.isEmpty) return null;
  return values.reduce((a, b) => a + b) / values.length;
}

String _amount(double v) => v.abs().toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '');

/// "weight down 4.2 lb", "energy up 0.8". Null when the change is too small to call.
String? describeChange(Metric m, double from, double to) {
  final d = to - from;
  if (d.abs() < m.minChange) return null;
  final unit = m.unit.isEmpty ? '' : ' ${m.unit}';
  return '${m.name} ${d < 0 ? 'down' : 'up'} ${_amount(d)}$unit';
}

/// Doses she logged for [c] since [from], against what her schedule planned.
({int logged, int planned}) adherence(Compound c, List<DoseLog> logs, DateTime from, DateTime now) {
  final logged = logs.where((l) => l.compoundId == c.id && !l.timestamp.isBefore(from)).length;
  final days = daysBetween(from, now) + 1;
  final planned = c.frequencyDays == 0 ? logged : (days / c.frequencyDays).ceil();
  return (logged: logged, planned: planned < logged ? logged : planned);
}

class CompoundOutcome {
  final Compound compound;
  final DateTime since;
  final List<String> changes;
  final ({int logged, int planned}) doses;
  const CompoundOutcome(this.compound, this.since, this.changes, this.doses);

  String get headline {
    final name = CompoundDirectory.shortName(compound.name);
    final when = DateFormat('MMM d').format(since);
    if (changes.isEmpty) {
      return 'Since you started $name on $when, nothing has clearly changed yet. That is common early on.';
    }
    final list = changes.length == 1
        ? changes.first
        : '${changes.sublist(0, changes.length - 1).join(', ')} and ${changes.last}';
    return 'Since you started $name on $when: $list.';
  }

  String get dosesLine {
    final d = doses;
    if (d.planned == 0) return '';
    final kept = 'You logged ${d.logged} of ${d.planned} planned doses';
    if (d.logged / d.planned >= 0.9) return '$kept, so this is a fair read.';
    if (d.logged / d.planned < 0.7) return '$kept. Missed doses make any change harder to read.';
    return '$kept.';
  }
}

class OutcomeReport {
  /// Day of logging, counted from her first dose.
  final int day;
  final List<CompoundOutcome> compounds;

  /// "Nausea: 3 days in your first week, none this week."
  final List<String> sideEffects;
  const OutcomeReport(this.day, this.compounds, this.sideEffects);

  bool get isReady => day >= outcomeStartDay;
  int get daysToGo => outcomeStartDay - day;
}

/// Null until she has logged a dose.
OutcomeReport? outcomeReport({
  required List<Compound> compounds,
  required List<DoseLog> logs,
  required List<DailyCheckIn> checkIns,
  required DateTime now,
}) {
  if (logs.isEmpty) return null;
  final first = logs.map((l) => l.timestamp).reduce((a, b) => a.isBefore(b) ? a : b);
  final day = daysBetween(first, now) + 1;
  if (day < outcomeStartDay) return OutcomeReport(day, const [], const []);

  final lastWeekStart = addDays(dayOf(now), -6);
  final tomorrow = addDays(dayOf(now), 1);
  final results = <CompoundOutcome>[];
  for (final c in compounds) {
    final own = logs.where((l) => l.compoundId == c.id).map((l) => l.timestamp).toList();
    if (own.isEmpty) continue;
    final since = dayOf(own.reduce((a, b) => a.isBefore(b) ? a : b));
    if (daysBetween(since, now) + 1 < outcomeStartDay) continue;

    final changes = <String>[];
    for (final m in metrics) {
      final before = averageBetween(checkIns, m, since, addDays(since, 7));
      final recent = averageBetween(checkIns, m, lastWeekStart, tomorrow);
      if (before == null || recent == null) continue;
      final line = describeChange(m, before, recent);
      if (line != null) changes.add(line);
    }
    results.add(CompoundOutcome(c, since, changes, adherence(c, logs, since, now)));
  }

  final firstWeekEnd = addDays(dayOf(first), 7);
  final effects = <String>[];
  for (final e in sideEffectOptions) {
    int count(DateTime from, DateTime to) =>
        checkIns.where((c) => !c.date.isBefore(from) && c.date.isBefore(to) && c.sideEffects.contains(e)).length;
    final early = count(dayOf(first), firstWeekEnd);
    final recent = count(lastWeekStart, tomorrow);
    if (early == 0 && recent == 0) continue;
    String days(int n) => n == 0 ? 'none' : '$n ${n == 1 ? 'day' : 'days'}';
    effects.add('$e: ${days(early)} in your first week, ${days(recent)} this week.');
  }
  return OutcomeReport(day, results, effects);
}

class WeeklyReport {
  final List<String> changed;
  final List<String> due;
  final List<String> watch;
  const WeeklyReport(this.changed, this.due, this.watch);

  bool get isEmpty => changed.isEmpty && due.isEmpty && watch.isEmpty;

  /// The one line a Sunday notification can carry.
  String get headline => changed.isNotEmpty
      ? changed.first
      : due.isNotEmpty
      ? due.first
      : 'Your week is in. Open it to see what changed.';
}

/// What changed this week against last week, what's due in the next seven days, and what to watch.
WeeklyReport weeklyReport({
  required List<Compound> compounds,
  required List<DoseLog> logs,
  required List<DailyCheckIn> checkIns,
  required bool hasCycle,
  required DateTime now,
}) {
  final today = dayOf(now);
  final thisWeek = addDays(today, -6);
  final lastWeek = addDays(today, -13);
  final tomorrow = addDays(today, 1);

  final changed = <String>[];
  for (final m in metrics) {
    final before = averageBetween(checkIns, m, lastWeek, thisWeek);
    final after = averageBetween(checkIns, m, thisWeek, tomorrow);
    if (before == null || after == null) continue;
    final line = describeChange(m, before, after);
    if (line != null) changed.add('${line[0].toUpperCase()}${line.substring(1)} on last week.');
  }
  final logged = logs.where((l) => !l.timestamp.isBefore(thisWeek)).length;
  final planned = plannedPerWeek(compounds);
  if (planned > 0) changed.add('$logged of $planned planned doses logged in the last 7 days.');

  final due = <String>[];
  for (final c in compounds.where((c) => c.isConfigured)) {
    final name = CompoundDirectory.shortName(c.name);
    final next = nextDueDay(c, logs);
    if (daysBetween(now, next) <= 7) due.add('$name, ${nextDoseLabel(c, logs)}, ${relativeDay(next, now)}.');
    final runout = runoutDay(c, logs);
    if (runout != null && daysBetween(now, runout) <= 7) due.add('$name runs out ${relativeDay(runout, now)}.');
    final expires = c.vialExpires;
    if (expires != null && daysBetween(now, expires) <= 7) {
      final d = daysBetween(now, expires);
      due.add(
        d < 0 ? "$name's mixed vial is past its date." : "$name's mixed vial expires ${relativeDay(expires, now)}.",
      );
    }
  }

  final watch = <String>[];
  final recent = checkIns.where((c) => !c.date.isBefore(thisWeek)).toList();
  for (final e in sideEffectOptions) {
    final n = recent.where((c) => c.sideEffects.contains(e)).length;
    if (n > 0) watch.add('$e on $n ${n == 1 ? 'day' : 'days'} this week.');
  }
  if (hasCycle) {
    final period = nextPeriodDue(checkIns);
    if (period != null && daysBetween(now, period) >= 0 && daysBetween(now, period) <= 7) {
      watch.add('Period likely ${relativeDay(period, now)}. Water weight around then is normal.');
    }
  }
  return WeeklyReport(changed, due, watch);
}

/// Spec page 6, "toned not frail": protein days at her target and how strong workouts felt, 0 to 100.
class TonedScore {
  final int score;
  final List<String> lines;
  const TonedScore(this.score, this.lines);
}

/// Null until she has a protein target with a logged day, or a strength rating in the last two weeks.
TonedScore? tonedScore(List<DailyCheckIn> checkIns, int? targetG, DateTime now) {
  final from = addDays(dayOf(now), -6);
  final protein = checkIns.where((c) => c.proteinG != null && !c.date.isBefore(from)).toList();
  final rated = checkIns.where((c) => c.strength != null).toList()..sort((a, b) => b.date.compareTo(a.date));
  final strength = rated.isEmpty || daysBetween(rated.first.date, now) > 13 ? null : rated.first.strength!;

  final parts = <double>[];
  final lines = <String>[];
  if (targetG != null && protein.isNotEmpty) {
    final hit = protein.where((c) => c.proteinG! >= targetG).length;
    parts.add(hit / 7);
    lines.add('Protein target hit on $hit of the last 7 days.');
  }
  if (strength != null) {
    parts.add((strength - 1) / 4);
    lines.add('Workouts felt $strength of 5 this week.');
  }
  if (parts.isEmpty) return null;
  return TonedScore((parts.reduce((a, b) => a + b) / parts.length * 100).round(), lines);
}

/// Spec: week-over-week deltas on a few tracked features, small numbers, no grades.
/// Compares her two latest photos where a face was found, adds her waist from check-ins
/// that week, and ties the read to a glow compound she's on. Observations only.
List<String> photoRead(
  List<ProgressPhoto> photos, {
  List<Compound> compounds = const [],
  List<DailyCheckIn> checkIns = const [],
}) {
  final scored = photos.where((p) => p.fullness != null).toList()..sort((a, b) => a.takenAt.compareTo(b.takenAt));
  if (scored.length < 2) return const [];
  final before = scored[scored.length - 2];
  final now = scored.last;
  final week = daysBetween(scored.first.takenAt, now.takenAt) ~/ 7 + 1;
  final lines = <String>[];

  final full = (now.fullness! - before.fullness!) / before.fullness! * 100;
  lines.add(
    full.abs() < 2
        ? 'Face fullness: about the same.'
        : 'Face fullness ${full < 0 ? 'down' : 'up'} ${full.abs().toStringAsFixed(0)}%.',
  );
  if (now.evenness != null && before.evenness != null) {
    final even = (now.evenness! - before.evenness!) * 100;
    lines.add(
      even.abs() < 2
          ? 'Skin evenness: about the same.'
          : 'Skin looks ${even > 0 ? 'more' : 'less'} even, ${even.abs().toStringAsFixed(0)} points.',
    );
  }
  final waist = metrics.firstWhere((m) => m.name == 'waist');
  double? waistNear(DateTime t) => averageBetween(checkIns, waist, addDays(dayOf(t), -3), addDays(dayOf(t), 4));
  final waistBefore = waistNear(before.takenAt);
  final waistNow = waistNear(now.takenAt);
  if (waistBefore != null && waistNow != null) {
    final change = describeChange(waist, waistBefore, waistNow);
    lines.add(change == null ? 'Waist: about the same.' : '${change[0].toUpperCase()}${change.substring(1)}.');
  }

  if (lines.every((l) => l.contains('about the same'))) {
    lines.add("No visible change yet. That's normal at week $week.");
  }

  final glow = compounds.where((c) => c.category == CompoundCategory.glowAndSkin && !c.startDate.isAfter(now.takenAt));
  if (glow.isNotEmpty) {
    final c = glow.first;
    lines.add(
      "That's week ${daysBetween(c.startDate, now.takenAt) ~/ 7 + 1} on ${CompoundDirectory.shortName(c.name)}.",
    );
  }
  return lines;
}
