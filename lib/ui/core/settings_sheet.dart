import 'dart:io';
import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_copy.dart';
import '../../core/theme/omnya_colors.dart';
import '../../core/theme/omnya_typography.dart';
import '../../core/widgets/omnya_controls.dart';
import '../../core/widgets/omnya_logo.dart';
import '../../core/widgets/omnya_toast.dart';
import '../../core/widgets/slide_page_route.dart';
import '../../data/repositories/protocol_repository.dart';
import '../../data/services/cloud_service.dart';
import '../../data/services/doctor_report.dart';
import '../../data/services/reminder_service.dart';
import '../../data/services/shotsy_import.dart';
import '../../data/services/subscription_service.dart';
import '../onboarding/onboarding_quiz_view.dart';
import '../onboarding/paywall_view.dart';
import 'app_lock.dart';
import 'sync_status_indicator.dart';

void showSettingsSheet(BuildContext context) {
  final repo = context.read<ProtocolRepository>();
  final reminders = context.read<ReminderService?>();
  showOmnyaSheet<void>(
    context,
    builder: (sheet) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Settings', style: OmnyaTypography.headline()),
        const SizedBox(height: 12),
        ListenableBuilder(
          listenable: repo,
          builder: (_, _) {
            final p = repo.profile;
            if (p == null) return const SizedBox.shrink();
            final time = TimeOfDay(hour: p.reminderMinutes ~/ 60, minute: p.reminderMinutes % 60);
            return Column(
              children: [
                _Switch(
                  icon: HugeIcons.strokeRoundedNotification01,
                  title: 'Dose reminders',
                  subtitle: p.remindersOn ? 'On dose days at ${time.format(sheet)}' : 'Off',
                  value: p.remindersOn,
                  onChanged: (v) => repo.updateSettings(p.copyWith(remindersOn: v)),
                ),
                if (p.remindersOn) ...[
                  _Row(
                    icon: HugeIcons.strokeRoundedClock01,
                    title: 'Reminder time',
                    subtitle: time.format(sheet),
                    onTap: () async {
                      final picked = await pickTime(sheet, title: 'Reminder time', initial: time);
                      if (picked != null) {
                        await repo.updateSettings(p.copyWith(reminderMinutes: picked.hour * 60 + picked.minute));
                      }
                    },
                  ),
                  _Row(
                    icon: HugeIcons.strokeRoundedNotificationSquare,
                    title: 'Send a test reminder',
                    subtitle: 'See one arrive right now',
                    onTap: () async {
                      final sent = await reminders?.sendTest() ?? false;
                      if (!sheet.mounted) return;
                      if (sent) {
                        OmnyaToast.show(
                          sheet,
                          title: 'Reminder sent',
                          message: 'Check your notification shade.',
                          type: OmnyaToastType.success,
                        );
                      } else {
                        OmnyaToast.show(
                          sheet,
                          title: 'Notifications are off',
                          message: 'Turn them on for Omnya in the Settings app.',
                          type: OmnyaToastType.warning,
                        );
                      }
                    },
                  ),
                ],
                _Switch(
                  icon: HugeIcons.strokeRoundedCameraSmile02,
                  title: 'Sunday photo reminder',
                  subtitle: 'A nudge each Sunday morning',
                  value: p.sundayPhotoPromptEnabled,
                  onChanged: (v) => repo.updateSettings(p.copyWith(sundayPhotoPromptEnabled: v)),
                ),
                _Switch(
                  icon: HugeIcons.strokeRoundedSquareLock02,
                  title: 'Lock with Face ID',
                  subtitle: 'Ask for Face ID when Omnya opens',
                  value: p.lockWithFaceId,
                  onChanged: (v) async {
                    // Turning it on proves Face ID works first, so she can't lock herself out.
                    if (v && !await unlockWithFaceId('Turn on Face ID lock')) return;
                    await repo.updateSettings(p.copyWith(lockWithFaceId: v));
                  },
                ),
              ],
            );
          },
        ),
        _Row(
          icon: HugeIcons.strokeRoundedQuiz03,
          title: 'Retake the quiz',
          subtitle: 'Update your goals, compounds and cycle answers',
          onTap: () {
            Navigator.pop(sheet);
            Navigator.push(context, SlidePageRoute(page: OnboardingQuizView(onFinished: () => Navigator.pop(context))));
          },
        ),
        Consumer<SubscriptionService>(
          builder: (ctx, sub, _) => _Row(
            icon: HugeIcons.strokeRoundedHonourStar,
            title: sub.isPro ? 'Omnya Pro (Active)' : 'Omnya Pro',
            subtitle: sub.isPro ? 'Your Pro subscription is active' : 'See what Pro includes',
            onTap: () {
              Navigator.pop(sheet);
              Navigator.push(context, SlidePageRoute(page: const PaywallView()));
            },
          ),
        ),
        ListenableBuilder(
          listenable: repo,
          builder: (_, _) => _Row(
            icon: repo.hasPendingSync ? HugeIcons.strokeRoundedCloudUpload : HugeIcons.strokeRoundedCloudSavingDone01,
            title: 'Backup',
            subtitle: backupStatusText(repo),
            trailing: repo.isSyncing ? const OmnyaLogoLoader(size: 24) : null,
            onTap: () => repo.sync(),
          ),
        ),
        _Row(
          icon: HugeIcons.strokeRoundedPdf01,
          title: 'Doctor report',
          subtitle: 'Your last 90 days as a PDF to share',
          onTap: () {
            if (context.read<SubscriptionService>().isPro) {
              _shareDoctorReport(sheet, repo);
            } else {
              Navigator.pop(sheet);
              openPaywall(context);
            }
          },
        ),
        _Row(
          icon: HugeIcons.strokeRoundedFileImport,
          title: 'Import from Shotsy',
          subtitle: 'Bring in past doses and weigh-ins from a CSV export',
          onTap: () {
            Navigator.pop(sheet);
            _importCsv(context, repo);
          },
        ),
        _Row(
          icon: HugeIcons.strokeRoundedDelete02,
          title: 'Delete my data',
          subtitle: 'From this phone and from backup',
          onTap: () {
            Navigator.pop(sheet);
            _confirmDelete(context, repo);
          },
        ),
        const SizedBox(height: 16),
        Text(AppCopy.medicalDisclaimer, style: OmnyaTypography.bodySmall()),
      ],
    ),
  );
}

Future<void> _shareDoctorReport(BuildContext context, ProtocolRepository repo) async {
  final box = context.findRenderObject() as RenderBox?;
  try {
    final bytes = await withLoadingOverlay(
      context,
      () => buildDoctorReport(repo, DateTime.now()),
      message: 'Making your report',
    );
    final file = File('${(await getTemporaryDirectory()).path}/omnya-report.pdf');
    await file.writeAsBytes(bytes);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/pdf')],
        sharePositionOrigin: box == null ? null : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
  } catch (e) {
    debugPrint('Doctor report failed: $e');
    if (context.mounted) {
      OmnyaToast.show(context, title: "Couldn't make the report", message: 'Try again.', type: OmnyaToastType.error);
    }
  }
}

Future<void> _importCsv(BuildContext context, ProtocolRepository repo) async {
  final file = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: const ['csv', 'txt']);
  if (file == null || !context.mounted) return;
  final data = parseShotsyCsv(await file.xFile.readAsString());
  if (!context.mounted) return;
  if (data.doses.isEmpty && data.weights.isEmpty) {
    OmnyaToast.show(
      context,
      title: 'Nothing to import',
      message: "That file doesn't have dates with doses or weights.",
      type: OmnyaToastType.warning,
    );
    return;
  }
  final added = await repo.importHistory(data);
  if (context.mounted) {
    OmnyaToast.show(
      context,
      title: 'Imported ${added.doses} doses and ${added.weights} weigh-ins',
      message: data.skipped == 0 ? null : '${data.skipped} rows could not be read.',
    );
  }
}

Future<void> _confirmDelete(BuildContext context, ProtocolRepository repo) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Delete all your data?', style: OmnyaTypography.headline()),
      content: Text(
        'This removes your stack, doses, check-ins and photos from this phone and from backup. '
        'It can\'t be undone.',
        style: OmnyaTypography.bodyMedium(),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(
            'Delete',
            style: OmnyaTypography.label(color: OmnyaColors.error, weight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  try {
    await withLoadingOverlay(context, repo.deleteAllData, message: 'Deleting your data');
  } on CloudException catch (e) {
    if (context.mounted) {
      OmnyaToast.show(context, title: 'Nothing was deleted', message: e.message, type: OmnyaToastType.error);
    }
  }
}

class _Switch extends StatelessWidget {
  final List<List<dynamic>> icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _Switch({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          HugeIcon(icon: icon, color: OmnyaColors.plum, size: 22),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: OmnyaTypography.label(weight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(subtitle, style: OmnyaTypography.bodySmall()),
              ],
            ),
          ),
          CNSwitch(value: value, onChanged: onChanged, color: OmnyaColors.plum),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final List<List<dynamic>> icon;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback onTap;

  const _Row({required this.icon, required this.title, required this.subtitle, required this.onTap, this.trailing});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            HugeIcon(icon: icon, color: OmnyaColors.plum, size: 22),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: OmnyaTypography.label(weight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: OmnyaTypography.bodySmall()),
                ],
              ),
            ),
            trailing ??
                const HugeIcon(icon: HugeIcons.strokeRoundedArrowRight01, color: OmnyaColors.taupeDark, size: 18),
          ],
        ),
      ),
    );
  }
}
