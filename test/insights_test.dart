import 'package:flutter_test/flutter_test.dart';
import 'package:omnya/core/constants/compound_directory.dart';
import 'package:omnya/data/models/compound.dart';
import 'package:omnya/data/models/daily_check_in.dart';
import 'package:omnya/data/models/dose_log.dart';
import 'package:omnya/domain/insights.dart';
import 'package:omnya/domain/schedule.dart';

final now = DateTime(2026, 9, 30, 9); // a Wednesday

Compound reta({int? left, int every = 7, DateTime? start}) => Compound(
  id: 'r',
  name: 'Retatrutide',
  nickname: '',
  category: CompoundCategory.body,
  dose: 2,
  frequencyDays: every,
  dosesLeft: left,
  startDate: start ?? DateTime(2026, 9, 1),
);

DoseLog log(DateTime at, {String id = 'l'}) =>
    DoseLog(id: id, compoundId: 'r', compoundName: 'Retatrutide', dose: 2, injectionSite: 'Left thigh', timestamp: at);

DailyCheckIn weigh(DateTime at, double lb, {bool period = false}) => DailyCheckIn(
  id: at.toIso8601String(),
  date: at,
  energyLevel: 3,
  appetiteLevel: 3,
  weightLbs: lb,
  periodStarted: period,
);

void main() {
  group('schedule', () {
    test('next dose is the start date until the first log, then last log + cadence', () {
      expect(nextDueDay(reta(start: DateTime(2026, 9, 28)), const []), DateTime(2026, 9, 28));
      expect(nextDueDay(reta(), [log(DateTime(2026, 9, 26, 20))]), DateTime(2026, 10, 3));
    });

    test('day math holds across daylight saving changes', () {
      expect(addDays(DateTime(2026, 11, 1), 1), DateTime(2026, 11, 2));
      expect(daysBetween(DateTime(2026, 10, 31), DateTime(2026, 11, 2)), 2);
      expect(daysBetween(DateTime(2026, 3, 7), DateTime(2026, 3, 9)), 2);
    });

    test('weeks start on Monday', () => expect(weekStartOf(now), DateTime(2026, 9, 28)));

    test('runout is the day of the last dose left', () {
      // Due Oct 3 (7 days after Sep 26), 2 doses left: Oct 3 and Oct 10.
      expect(runoutDay(reta(left: 2), [log(DateTime(2026, 9, 26))]), DateTime(2026, 10, 10));
      expect(runoutDay(reta(), const []), isNull, reason: 'not tracking the vial');
    });

    test('planned doses per week', () {
      expect(plannedPerWeek([reta(every: 1), reta(every: 7), reta(every: 3)]), 7 + 1 + 2);
    });

    test('labels', () {
      expect(relativeDay(DateTime(2026, 9, 30), now), 'today');
      expect(relativeDay(DateTime(2026, 10, 1), now), 'tomorrow');
      expect(relativeDay(DateTime(2026, 10, 3), now), 'Saturday');
      expect(relativeDay(DateTime(2026, 11, 3), now), 'Nov 3');
      expect(formatDose(2), '2 mg');
      expect(formatDose(0.25), '0.25 mg');
      expect(everyLabel(7), 'weekly');
    });
  });

  group('today insight', () {
    test('nothing to say without data', () {
      expect(todayInsight(compounds: const [], logs: const [], checkIns: const [], hasCycle: true, now: now), isNull);
    });

    test('runout within a week comes first', () {
      final i = todayInsight(
        compounds: [reta(left: 1)],
        logs: [log(DateTime(2026, 9, 26))],
        checkIns: const [],
        hasCycle: false,
        now: now,
      );
      expect(i!.text, 'Reta runs out Saturday.');
    });

    test('scale up before a period reads as water weight, with her real numbers', () {
      final i = todayInsight(
        compounds: const [],
        logs: const [],
        checkIns: [
          weigh(DateTime(2026, 9, 5), 140, period: true),
          weigh(DateTime(2026, 9, 23), 140.5),
          weigh(DateTime(2026, 9, 30), 142.5),
        ],
        hasCycle: true,
        now: now,
      );
      expect(i!.text, "Scale's up 2 lb, period's due Saturday. Ignore it.");
    });

    test('weight going up is never framed as a result', () {
      final i = todayInsight(
        compounds: const [],
        logs: const [],
        checkIns: [weigh(DateTime(2026, 9, 1), 140), weigh(DateTime(2026, 9, 29), 143)],
        hasCycle: false,
        now: now,
      );
      expect(i, isNull);
    });

    test('a downward trend over a week or more', () {
      final i = todayInsight(
        compounds: const [],
        logs: const [],
        checkIns: [weigh(DateTime(2026, 9, 1), 145), weigh(DateTime(2026, 9, 29), 141.6)],
        hasCycle: false,
        now: now,
      );
      expect(i!.text, 'Down 3.4 lb since Sep 1.');
    });
  });

  test('progress highlight uses her weigh-ins, with a real minus sign', () {
    final h = progressHighlight([weigh(DateTime(2026, 9, 1), 145), weigh(DateTime(2026, 9, 29), 141.6)], now);
    expect(h!.stat, '−3.4 lb');
    expect(h.caption, 'since Sep 1');
  });

  group('milestones', () {
    test('first dose shows once', () {
      expect(milestoneAfterLog([log(now)], {}, now), Milestone.firstDose);
      expect(milestoneAfterLog([log(now)], {'firstDose'}, now), isNull);
    });

    test('day 30 only during its week', () {
      final first = log(DateTime(2026, 9, 1), id: 'a');
      expect(
        milestoneAfterLog([log(DateTime(2026, 9, 30)), first], {'firstDose'}, DateTime(2026, 9, 30)),
        Milestone.day30,
      );
      expect(milestoneAfterLog([log(DateTime(2026, 11, 20)), first], {'firstDose'}, DateTime(2026, 11, 20)), isNull);
    });
  });
}
