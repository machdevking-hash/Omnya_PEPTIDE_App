import 'package:flutter_test/flutter_test.dart';
import 'package:omnya/data/services/shotsy_import.dart';
import 'fakes.dart';

const csv = '''Date,Medication,Dose,Injection Site,Weight (lbs),Notes
2026-08-01 08:30,Retatrutide,2 mg,Left Thigh,168.4,"first shot, felt ""fine"""
08/08/2026 8:00 PM,Retatrutide,2.5,right abdomen,,
2026-08-10,,,,166.0,
not a date,Retatrutide,2,,,
''';

void main() {
  test('reads a shot-tracker CSV: doses, weights, sites, formats', () {
    final r = parseShotsyCsv(csv);
    expect(r.doses.length, 2);
    expect(r.doses.first.site, 'Left thigh');
    expect(r.doses[1].dose, 2.5);
    expect(r.doses[1].at, DateTime(2026, 8, 8, 20));
    expect(r.doses[1].site, 'Right abdomen');
    expect(r.weights.map((w) => w.lbs), [168.4, 166.0]);
    expect(r.skipped, 1);
    expect(parseAmount('250mcg', 'mg'), (250.0, 'mcg'));
  });

  test('importing twice adds nothing the second time', () async {
    final repo = await makeRepo(FakeCloud());
    final data = parseShotsyCsv(csv);
    expect(await repo.importHistory(data), (doses: 2, weights: 2));
    expect(await repo.importHistory(data), (doses: 0, weights: 0));
    expect(repo.compounds.single.name, 'Retatrutide');
    expect(repo.compounds.single.startDate, DateTime(2026, 8, 1));
    expect(repo.checkIns.first.energyLevel, isNull);
    await settle();
    repo.dispose();
  });
}
