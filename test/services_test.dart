import 'package:flutter_test/flutter_test.dart';
import 'package:omnya/data/models/user_profile.dart';
import 'package:omnya/data/services/doctor_report.dart';
import 'package:omnya/data/services/reminder_service.dart';
import 'fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('reminders: dose days at her time, Sundays, nothing when off', () async {
    final repo = await makeRepo(FakeCloud());
    await repo.completeOnboarding(UserProfile(createdAt: DateTime(2026, 9, 1)), const []);
    final c = repo.newCompound('Retatrutide', startDate: DateTime(2026, 10, 1)).copyWith(dose: 2, frequencyDays: 7);
    await repo.saveCompound(c);
    final now = DateTime(2026, 9, 30, 12); // Wednesday
    final planned = plannedReminders(repo, now);
    final dose = planned.where((r) => r.route == 'today').toList();
    expect(dose.first.at, DateTime(2026, 10, 1, 9));
    expect(dose.first.title, "Reta's ready when you are");
    expect(dose[1].at, DateTime(2026, 10, 8, 9));
    expect(planned.where((r) => r.route == 'photo').first.at, DateTime(2026, 10, 4, 10));
    expect(planned.every((r) => r.at.isAfter(now)), isTrue);

    await repo.updateSettings(repo.profile!.copyWith(remindersOn: false));
    expect(plannedReminders(repo, now), isEmpty);
    await settle();
    repo.dispose();
  });

  test('doctor report renders a PDF', () async {
    final repo = await makeRepo(FakeCloud());
    await repo.saveCompound(repo.newCompound('Retatrutide').copyWith(dose: 2, frequencyDays: 7));
    await repo.logDose(repo.compounds.single.id);
    final pdf = await buildDoctorReport(repo, DateTime.now());
    expect(String.fromCharCodes(pdf.take(5)), '%PDF-');
    await settle();
    repo.dispose();
  });
}
