import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/omnya_colors.dart';
import '../../../core/theme/omnya_typography.dart';
import '../../../core/widgets/omnya_card.dart';
import '../../../core/widgets/omnya_logo.dart';
import '../../../core/widgets/omnya_toast.dart';
import '../../../core/widgets/tactile_button.dart';
import '../../../data/models/progress_photo.dart';
import '../../../data/repositories/protocol_repository.dart';
import '../../../domain/outcomes.dart';
import '../../../domain/schedule.dart';
import '../../onboarding/paywall_view.dart';
import '../progress/progress_card_sheet.dart';

/// Spec page 3: one photo a week, same setup, compared with last week.
/// Photos are saved on this phone only.
class WeeklyPhotoView extends StatelessWidget {
  const WeeklyPhotoView({super.key});

  Future<void> _save(BuildContext context, Future<Uint8List?> Function() capture) async {
    final repo = context.read<ProtocolRepository>();
    final bytes = await capture();
    if (bytes == null) return;
    await repo.addPhoto(bytes);
    if (context.mounted) {
      OmnyaToast.show(context, title: "This week's photo is saved", message: 'It stays on this phone.');
    }
  }

  Future<Uint8List?> _fromLibrary() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1600, imageQuality: 85);
    return picked?.readAsBytes();
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<ProtocolRepository>();
    final read = photoRead(repo.photos, compounds: repo.compounds, checkIns: repo.checkIns);
    final now = DateTime.now();
    final thisWeek = repo.photoInWeekOf(now);
    final lastWeek = repo.photoInWeekOf(addDays(now, -7));
    final ghost = thisWeek ?? lastWeek ?? (repo.photos.isEmpty ? null : repo.photos.last);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          icon: const HugeIcon(icon: HugeIcons.strokeRoundedArrowLeft01, color: OmnyaColors.charcoal, size: 22),
          onPressed: () => Navigator.pop(context),
        ),
        titleSpacing: 0,
        title: Text('Your week in photos', style: OmnyaTypography.headline()),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 32),
        children: [
          Row(
            children: [
              Expanded(
                child: _Slot(label: 'Last week', photo: lastWeek, repo: repo),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _Slot(label: 'This week', photo: thisWeek, repo: repo),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TactileButton(
            label: thisWeek == null ? "Take this week's photo" : "Retake this week's photo",
            width: double.infinity,
            leading: const HugeIcon(icon: HugeIcons.strokeRoundedCameraSmile02, color: OmnyaColors.cream, size: 18),
            onPressed: () => _save(
              context,
              () => Navigator.push<Uint8List>(
                context,
                MaterialPageRoute(
                  fullscreenDialog: true,
                  builder: (_) => _CameraScreen(ghost: ghost == null ? null : repo.photoFile(ghost).path),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          TactileButton(
            label: 'Choose from library',
            variant: TactileButtonVariant.outline,
            width: double.infinity,
            onPressed: () => _save(context, _fromLibrary),
          ),
          const SizedBox(height: 8),
          Center(child: Text('Photos stay on this phone.', style: OmnyaTypography.bodySmall())),
          const SizedBox(height: 20),
          OmnyaCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Weekly read', style: OmnyaTypography.label(weight: FontWeight.w600)),
                const SizedBox(height: 8),
                if (read.isEmpty)
                  Text(
                    'After two weekly photos with your face in frame, a short note on what changed shows up here. '
                    'Measured on this phone.',
                    style: OmnyaTypography.bodyMedium(),
                  )
                else
                  ProGate(
                    message: 'Your read is ready. See it with Pro.',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final line in read)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(line, style: OmnyaTypography.bodyLarge(color: OmnyaColors.charcoal)),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          if (repo.photos.isNotEmpty) ...[
            const SizedBox(height: 16),
            TactileButton(
              label: 'Share this week',
              variant: TactileButtonVariant.secondary,
              width: double.infinity,
              onPressed: () => showProgressCard(context),
            ),
          ],
        ],
      ),
    );
  }
}

class _Slot extends StatelessWidget {
  final String label;
  final ProgressPhoto? photo;
  final ProtocolRepository repo;
  const _Slot({required this.label, required this.photo, required this.repo});

  @override
  Widget build(BuildContext context) {
    final p = photo;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          p == null ? label : '$label · ${DateFormat('MMM d').format(p.takenAt)}',
          style: OmnyaTypography.tag(color: OmnyaColors.taupeDark),
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(OmnyaRadius.card),
          child: AspectRatio(
            aspectRatio: 3 / 4,
            child: p == null
                ? Container(
                    decoration: BoxDecoration(
                      color: OmnyaColors.sandMuted,
                      border: Border.all(color: OmnyaColors.line),
                      borderRadius: BorderRadius.circular(OmnyaRadius.card),
                    ),
                    alignment: Alignment.center,
                    child: const HugeIcon(icon: HugeIcons.strokeRoundedImage01, color: OmnyaColors.taupeDark, size: 26),
                  )
                : Image.file(repo.photoFile(p), fit: BoxFit.cover, gaplessPlayback: true),
          ),
        ),
      ],
    );
  }
}

/// Full-screen camera. It only runs while this screen is open, and it lets go of
/// the camera whenever the app leaves the foreground.
class _CameraScreen extends StatefulWidget {
  final String? ghost;
  const _CameraScreen({this.ghost});

  @override
  State<_CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<_CameraScreen> with WidgetsBindingObserver {
  List<CameraDescription> _cameras = const [];
  CameraController? _controller;
  int _index = 0;
  String? _problem;
  bool _busy = false;
  bool _switching = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      final c = _controller;
      _controller = null;
      c?.dispose();
      if (mounted) setState(() {});
    } else if (state == AppLifecycleState.resumed && _controller == null) {
      _start(index: _index);
    }
  }

  Future<void> _start({int? index}) async {
    try {
      if (_cameras.isEmpty) _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        if (mounted) {
          setState(
            () => _problem = 'No camera found on this device. You can choose a photo from your library instead.',
          );
        }
        return;
      }
      final front = _cameras.indexWhere((c) => c.lensDirection == CameraLensDirection.front);
      final back = _cameras.indexWhere((c) => c.lensDirection == CameraLensDirection.back);
      _index = index ?? (front != -1 ? front : (back != -1 ? back : 0));

      // CRITICAL FOR ANDROID CAMERAX: Disposing the previous controller AFTER
      // initializing the new one causes CameraX to unbind all use cases and
      // release the preview surface provider, leaving a black screen.
      // The previous controller MUST be disposed first.
      final old = _controller;
      _controller = null;
      if (mounted) setState(() {});
      await old?.dispose();

      final controller = CameraController(_cameras[_index], ResolutionPreset.high, enableAudio: false);
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _problem = null;
      });
    } on CameraException catch (e) {
      debugPrint('Camera: ${e.code} ${e.description}');
      if (mounted) {
        setState(
          () => _problem = e.code.contains('AccessDenied')
              ? 'Camera access is off. Turn it on in Settings, or choose a photo from your library.'
              : "The camera didn't start. Close this and try again.",
        );
      }
    }
  }

  Future<void> _flip() async {
    if (_cameras.length < 2 || _busy || _switching) return;
    setState(() => _switching = true);
    HapticFeedback.lightImpact();
    try {
      final currentDirection = _cameras[_index].lensDirection;
      final targetDirection = currentDirection == CameraLensDirection.front
          ? CameraLensDirection.back
          : CameraLensDirection.front;

      // Find the primary camera matching targetDirection, fallback to cycling.
      var nextIndex = _cameras.indexWhere((c) => c.lensDirection == targetDirection);
      if (nextIndex == -1) {
        nextIndex = (_index + 1) % _cameras.length;
      }
      await _start(index: nextIndex);
    } finally {
      if (mounted) {
        setState(() => _switching = false);
      }
    }
  }

  Future<void> _capture() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized || _busy || _switching) return;
    setState(() => _busy = true);
    HapticFeedback.mediumImpact();
    try {
      final shot = await c.takePicture();
      final bytes = await shot.readAsBytes();
      if (mounted) Navigator.pop(context, bytes);
    } on CameraException catch (e) {
      debugPrint('Capture failed: ${e.code}');
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    final ready = c != null && c.value.isInitialized;

    return Scaffold(
      backgroundColor: OmnyaColors.charcoal,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Close camera',
                    onPressed: () => Navigator.pop(context),
                    icon: const HugeIcon(icon: HugeIcons.strokeRoundedCancel01, color: OmnyaColors.cream, size: 22),
                  ),
                  Expanded(
                    child: Text(
                      "This week's photo",
                      textAlign: TextAlign.center,
                      style: OmnyaTypography.label(color: OmnyaColors.cream, weight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(OmnyaRadius.card),
                  child: Container(
                    color: const Color(0xFF2A2624),
                    child: _problem != null
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(28),
                              child: Text(
                                _problem!,
                                textAlign: TextAlign.center,
                                style: OmnyaTypography.bodyMedium(color: OmnyaColors.sandMuted),
                              ),
                            ),
                          )
                        : !ready
                        ? const Center(child: OmnyaLogoLoader(size: 48, onDark: true))
                        : Stack(
                            fit: StackFit.expand,
                            children: [
                              FittedBox(
                                fit: BoxFit.cover,
                                child: SizedBox(
                                  width: () {
                                    final p = c.value.previewSize;
                                    if (p == null) return 3.0;
                                    return p.width > p.height ? p.height : p.width;
                                  }(),
                                  height: () {
                                    final p = c.value.previewSize;
                                    if (p == null) return 4.0;
                                    return p.width > p.height ? p.width : p.height;
                                  }(),
                                  child: CameraPreview(c),
                                ),
                              ),
                              if (widget.ghost != null)
                                IgnorePointer(
                                  child: Opacity(
                                    opacity: 0.3,
                                    child: Image.file(File(widget.ghost!), fit: BoxFit.cover),
                                  ),
                                ),
                            ],
                          ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              widget.ghost != null ? "Line up with last week's photo" : 'Face the camera in soft, even light',
              style: OmnyaTypography.bodySmall(color: OmnyaColors.sandMuted),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 18, 32, 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const SizedBox(width: 48),
                  Semantics(
                    button: true,
                    label: 'Take photo',
                    child: GestureDetector(
                      onTap: ready && !_busy && !_switching ? _capture : null,
                      child: AnimatedOpacity(
                        opacity: ready && !_busy && !_switching ? 1 : 0.4,
                        duration: const Duration(milliseconds: 150),
                        child: Container(
                          width: 76,
                          height: 76,
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: OmnyaColors.cream, width: 3),
                          ),
                          child: const DecoratedBox(
                            decoration: BoxDecoration(shape: BoxShape.circle, color: OmnyaColors.cream),
                          ),
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Flip camera',
                    onPressed: _cameras.length > 1 && !_switching && !_busy ? _flip : null,
                    style: IconButton.styleFrom(
                      backgroundColor: OmnyaColors.cream.withValues(alpha: 0.12),
                      fixedSize: const Size(48, 48),
                    ),
                    icon: HugeIcon(
                      icon: HugeIcons.strokeRoundedFlipHorizontal,
                      color: _cameras.length > 1 && !_switching && !_busy
                          ? OmnyaColors.cream
                          : OmnyaColors.cream.withValues(alpha: 0.3),
                      size: 22,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
