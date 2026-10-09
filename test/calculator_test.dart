import 'package:flutter_test/flutter_test.dart';
import 'package:omnya/domain/reconstitution_calculator.dart';

void main() {
  test('10 mg vial, 2 mL water, 2 mg dose', () {
    final r = ReconstitutionCalculator.calculate(vialMg: 10, bacWaterMl: 2, targetDoseMg: 2, vialCost: 45);
    expect(r.concentrationMgPerMl, 5);
    expect(r.doseVolumeMl, 0.4);
    expect(r.u100Units, 40);
    expect(r.u40Units, 16);
    expect(r.totalDosesPerVial, 5);
    expect(r.costPerDose, 9);
  });

  test('empty or zero inputs give zeros, not errors', () {
    final r = ReconstitutionCalculator.calculate(vialMg: 0, bacWaterMl: 0, targetDoseMg: 0);
    expect(r.u100Units, 0);
    expect(r.totalDosesPerVial, 0);
  });
}
