import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnya/data/models/user_profile.dart';
import 'package:omnya/data/services/cloud_service.dart';
import 'package:omnya/domain/insights.dart';
import 'fakes.dart';

void main() {
  late FakeCloud cloud;
  setUp(() => cloud = FakeCloud());

  test('a fresh install starts empty: no demo compounds, circle members or weigh-ins', () async {
    final repo = await makeRepo(cloud);
    expect(repo.compounds, isEmpty);
    expect(repo.doseLogs, isEmpty);
    expect(repo.checkIns, isEmpty);
    expect(repo.circle, isNull);
    expect(repo.profile, isNull);
    await settle();
    repo.dispose();
  });

  test('demo rows seeded by older builds are removed, real rows are kept', () async {
    final repo = await makeRepo(
      cloud,
      prefs: {
        'omnya_compounds': jsonEncode([
          {
            'id': 'reta_01',
            'name': 'Retatrutide',
            'nickname': 'Dream bod, here we come.',
            'category': 'body',
            'doseMg': 2.0,
            'frequencyDays': 7,
            'injectionSite': 'Left thigh',
            'vialMg': 10.0,
            'bacWaterMl': 2.0,
            'dosesLeft': 3,
            'costPerDose': 4.1,
            'totalMonthlyCost': 16.4,
            'startDate': '2026-09-01T00:00:00.000',
            'runoutDate': '2026-09-20T00:00:00.000',
          },
          {
            'id': 'mine',
            'name': 'GHK-Cu',
            'nickname': '',
            'category': 'glowAndSkin',
            'doseMg': 1.5,
            'frequencyDays': 1,
            'injectionSite': 'Abdomen',
            'startDate': '2026-09-01T00:00:00.000',
          },
        ]),
        'omnya_check_ins': jsonEncode([
          {'id': 'chk_01', 'date': '2026-09-24T09:00:00.000', 'energyLevel': 4, 'appetiteLevel': 2, 'weightLbs': 141.2},
        ]),
        'omnya_circle': jsonEncode({
          'id': 'circ_omnya_default',
          'inviteCode': 'OMNYA',
          'name': 'Sunday Glow',
          'members': [],
        }),
      },
    );
    expect(repo.compounds.map((c) => c.id), ['mine']);
    expect(repo.compounds.single.nextSite, 'Abdomen', reason: 'old `injectionSite` key still reads');
    expect(repo.checkIns, isEmpty);
    expect(repo.circle, isNull);
    await settle();
    repo.dispose();
  });

  test('onboarding adds the compounds she named, with no dose or schedule filled in', () async {
    final repo = await makeRepo(cloud);
    await repo.completeOnboarding(UserProfile(createdAt: DateTime.now()), ['Retatrutide', 'GHK-Cu']);
    expect(repo.compounds.map((c) => c.name), ['Retatrutide', 'GHK-Cu']);
    expect(repo.compounds.every((c) => !c.isConfigured && c.dose == 0 && c.frequencyDays == 0), isTrue);
    expect(repo.compounds.first.nickname, 'Dream bod, here we come.');

    await repo.completeOnboarding(UserProfile(createdAt: DateTime.now()), ['Retatrutide']);
    expect(repo.compounds.length, 2, reason: 'retaking the quiz does not duplicate compounds');
    await settle();
    repo.dispose();
  });

  test('logging rotates the site and counts down the vial; undo restores both and deletes the cloud row', () async {
    final repo = await makeRepo(cloud);
    final reta = repo
        .newCompound('Retatrutide')
        .copyWith(dose: 2, frequencyDays: 7, nextSite: 'Left thigh', dosesLeft: () => 4);
    await repo.saveCompound(reta);

    final first = await repo.logDose(reta.id);
    expect(first.log.injectionSite, 'Left thigh');
    expect(first.milestone, Milestone.firstDose);
    expect(repo.compounds.single.nextSite, 'Right thigh');
    expect(repo.compounds.single.dosesLeft, 3);

    final second = await repo.logDose(reta.id);
    expect(second.milestone, isNull, reason: 'the first-dose moment shows once');
    await repo.undoDose(second.log);
    expect(repo.doseLogs.map((l) => l.id), [first.log.id]);
    expect(repo.compounds.single.nextSite, 'Right thigh');
    expect(repo.compounds.single.dosesLeft, 3);

    await settle();
    expect(await repo.sync(), isTrue);
    expect(cloud.lastDeletes.map((d) => (d.table, d.id)), [('dose_logs', second.log.id)]);
    await repo.sync();
    expect(cloud.lastDeletes, isEmpty, reason: 'the delete queue clears once sent');
    await settle();
    repo.dispose();
  });

  test('offline changes stay on the phone and back up when the network returns', () async {
    cloud.offline = true;
    final repo = await makeRepo(cloud);
    await settle();
    await repo.saveCheckIn(energy: 4, appetite: 2, weightLbs: 141.5);
    expect(await repo.sync(), isFalse);
    expect(repo.hasPendingSync, isTrue);
    expect(repo.syncError, isNotNull);
    expect(repo.checkIns.single.weightLbs, 141.5);

    cloud.offline = false;
    expect(await repo.sync(), isTrue);
    expect(repo.hasPendingSync, isFalse);
    expect(repo.syncError, isNull);
    await settle();
    repo.dispose();
  });

  test('one check-in per day: saving again edits today', () async {
    final repo = await makeRepo(cloud);
    await repo.saveCheckIn(energy: 2, appetite: 3);
    await repo.saveCheckIn(energy: 5, appetite: 1, periodStarted: true);
    expect(repo.checkIns.length, 1);
    expect(repo.checkIns.single.energyLevel, 5);
    expect(repo.checkIns.single.periodStarted, isTrue);
    await settle();
    repo.dispose();
  });

  test('circle: start, then leave', () async {
    final repo = await makeRepo(cloud);
    await repo.createCircle('  Bea ');
    expect(repo.circle!.name, "Bea's circle");
    await repo.leaveCircle();
    expect(repo.circle, isNull);
    await expectLater(repo.joinCircle('ZZZZZ', 'Bea'), throwsA(isA<CloudException>()));
    await repo.joinCircle('p3rx9', 'Bea');
    expect(repo.circle!.members.length, 2);
    await settle();
    repo.dispose();
  });

  test('delete my data: nothing is removed when the cloud copy is unreachable', () async {
    final repo = await makeRepo(cloud);
    await repo.saveCheckIn(energy: 3, appetite: 3);
    cloud.offline = true;
    await expectLater(repo.deleteAllData(), throwsA(isA<CloudException>()));
    expect(repo.checkIns, isNotEmpty);

    cloud.offline = false;
    await repo.deleteAllData();
    expect(cloud.deleted, isTrue);
    expect(repo.checkIns, isEmpty);
    expect(repo.profile, isNull);
    await settle();
    repo.dispose();
  });
}
