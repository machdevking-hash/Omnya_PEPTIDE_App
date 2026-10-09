import 'package:flutter_test/flutter_test.dart';
import 'package:omnya/data/models/compound.dart';
import 'package:omnya/data/models/dose_log.dart';
import 'package:omnya/core/constants/compound_directory.dart';
import 'package:omnya/data/models/daily_check_in.dart';
import 'package:omnya/data/models/progress_photo.dart';
import 'package:omnya/domain/outcomes.dart';
import 'package:omnya/domain/schedule.dart';
import 'insights_test.dart' show reta, log, now;

DailyCheckIn day(DateTime at, {double? lb, double? waist, List<String> effects = const []}) => DailyCheckIn(
  id: at.toIso8601String(),
  date: at,
  energyLevel: 3,
  appetiteLevel: 3,
  weightLbs: lb,
  waistIn: waist,
  sideEffects: effects,
);

void main() {
  test('titration: the latest started step sets the dose', () {
    final c = reta().copyWith(
      titration: [TitrationStep(DateTime(2026, 9, 10), 4), TitrationStep(DateTime(2026, 10, 10), 6)],
    );
    expect(c.doseOn(DateTime(2026, 9, 5)), 2);
    expect(c.doseOn(DateTime(2026, 9, 30)), 4);
    expect(c.doseOn(DateTime(2026, 10, 10)), 6);
    expect(formatDose(500, 'mcg'), '500 mcg');
  });

  test('outcome engine waits for day 14, then reads changes and doses kept', () {
    final start = DateTime(2026, 9, 2, 8);
    final logs = [for (var w = 0; w < 5; w++) log(addDays(start, w * 7), id: 'l$w')];
    final checkIns = [
      day(DateTime(2026, 9, 2), lb: 160, waist: 31, effects: ['Nausea']),
      day(DateTime(2026, 9, 4), lb: 159.6, effects: ['Nausea']),
      day(DateTime(2026, 9, 27), lb: 155.2, waist: 30),
      day(DateTime(2026, 9, 29), lb: 154.8),
    ];

    final early = outcomeReport(
      compounds: [reta()],
      logs: logs.take(1).toList(),
      checkIns: checkIns,
      now: DateTime(2026, 9, 10),
    );
    expect(early!.isReady, isFalse);
    expect(early.daysToGo, 5);

    final r = outcomeReport(compounds: [reta()], logs: logs, checkIns: checkIns, now: now)!;
    expect(r.isReady, isTrue);
    final o = r.compounds.single;
    expect(o.changes, containsAll(['weight down 4.8 lb', 'waist down 1 in']));
    expect(o.doses, (logged: 5, planned: 5));
    expect(o.dosesLine, contains('fair read'));
    expect(r.sideEffects.single, 'Nausea: 2 days in your first week, none this week.');
  });

  test('weekly report: change on last week, what is due, vial expiry', () {
    final c = reta(left: 3).copyWith(mixedOn: () => DateTime(2026, 9, 5), vialDays: () => 28);
    final report = weeklyReport(
      compounds: [c],
      logs: [log(DateTime(2026, 9, 26, 8))],
      checkIns: [day(DateTime(2026, 9, 20), lb: 158), day(DateTime(2026, 9, 29), lb: 156)],
      hasCycle: false,
      now: now,
    );
    expect(report.changed.first, 'Weight down 2 lb on last week.');
    expect(report.due, contains("Reta's mixed vial expires Saturday."));
  });

  test('toned score: protein days at target and the latest strength rating', () {
    DailyCheckIn fed(DateTime at, {int? g, int? strength}) =>
        DailyCheckIn(id: at.toIso8601String(), date: at, proteinG: g, strength: strength);
    expect(tonedScore([], 100, now), isNull);
    expect(tonedScore([fed(now, g: 120)], null, now), isNull);

    final week = [
      for (var i = 0; i < 4; i++) fed(addDays(now, -i), g: 110),
      fed(addDays(now, -4), g: 60),
      fed(addDays(now, -9), g: 200), // outside the week
      fed(addDays(now, -2), strength: 5),
    ];
    final s = tonedScore(week, 100, now)!;
    expect(s.lines, ['Protein target hit on 4 of the last 7 days.', 'Workouts felt 5 of 5 this week.']);
    expect(s.score, ((4 / 7 + 1) / 2 * 100).round());

    // A strength rating older than two weeks no longer counts.
    expect(tonedScore([fed(addDays(now, -20), strength: 4)], null, now), isNull);
  });

  test('body map: last use per site across compounds, rest window', () {
    final used = siteLastUsed([
      log(addDays(now, -9), id: 'a'),
      log(addDays(now, -2), id: 'b'),
      DoseLog(id: 'c', compoundId: 'o', compoundName: 'BPC-157', dose: 1, injectionSite: '', timestamp: now),
    ]);
    expect(used.keys, ['Left thigh']);
    expect(daysBetween(used['Left thigh']!, now), 2);
    expect(daysBetween(used['Left thigh']!, now) < siteRestDays, isTrue);
  });

  test('photo read adds waist and the glow compound week, observations only', () {
    final photos = [
      ProgressPhoto(id: '1', takenAt: DateTime(2026, 9, 6), fileName: 'a', fullness: 1, evenness: 0.8),
      ProgressPhoto(id: '2', takenAt: DateTime(2026, 9, 13), fileName: 'b', fullness: 1, evenness: 0.8),
    ];
    final ghk = Compound(
      id: 'g',
      name: 'GHK-Cu',
      nickname: '',
      category: CompoundCategory.glowAndSkin,
      startDate: DateTime(2026, 8, 20),
    );
    final lines = photoRead(
      photos,
      compounds: [reta(), ghk],
      checkIns: [day(DateTime(2026, 9, 6), waist: 30), day(DateTime(2026, 9, 13), waist: 29.5)],
    );
    expect(lines, [
      'Face fullness: about the same.',
      'Skin evenness: about the same.',
      'Waist down 0.5 in.',
      "That's week 4 on GHK-Cu.",
    ]);
    expect(photoRead(photos).last, "No visible change yet. That's normal at week 2.");
  });
}
