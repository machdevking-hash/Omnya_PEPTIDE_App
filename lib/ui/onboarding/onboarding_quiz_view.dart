import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_copy.dart';
import '../../core/constants/compound_directory.dart';
import '../../core/theme/omnya_colors.dart';
import '../../core/theme/omnya_typography.dart';
import '../../core/widgets/omnya_logo.dart';
import '../../core/widgets/slide_page_route.dart';
import '../../core/widgets/tactile_button.dart';
import '../../data/models/user_profile.dart';
import '../../data/repositories/protocol_repository.dart';
import '../features/today/milestone_view.dart';
import 'paywall_view.dart';

/// Spec page 5: six questions, one per screen, then her protocol, then the plans.
/// Nothing is pre-selected. With [onFinished] it is a retake from settings.
class OnboardingQuizView extends StatefulWidget {
  final VoidCallback? onFinished;
  const OnboardingQuizView({super.key, this.onFinished});

  @override
  State<OnboardingQuizView> createState() => _OnboardingQuizViewState();
}

class _OnboardingQuizViewState extends State<OnboardingQuizView> {
  static const _steps = 6;
  int _step = 0; // 0-5 questions, 6 = protocol summary
  final _goals = <String>{};
  final _compounds = <String>{};
  String? _experience;
  String? _cycle;
  String? _photoType;
  final _goalText = TextEditingController();

  bool get _isRetake => widget.onFinished != null;

  @override
  void dispose() {
    _goalText.dispose();
    super.dispose();
  }

  bool get _answered => switch (_step) {
    0 => _goals.isNotEmpty,
    1 => _compounds.isNotEmpty,
    2 => _experience != null,
    3 => _cycle != null,
    4 => true, // her words are optional
    5 => _photoType != null,
    _ => true,
  };

  void _next() {
    HapticFeedback.lightImpact();
    FocusScope.of(context).unfocus();
    if (_step < _steps) {
      setState(() => _step++);
    } else {
      _finish();
    }
  }

  void _back() {
    HapticFeedback.lightImpact();
    if (_step > 0) {
      setState(() => _step--);
    } else {
      Navigator.maybePop(context);
    }
  }

  List<String> get _compoundNames => _compounds.where((c) => c != 'Not sure yet').toList();

  Future<void> _finish() async {
    final repo = context.read<ProtocolRepository>();
    final profile = UserProfile(
      goals: _goals.toList(),
      selectedCompounds: _compounds.toList(),
      experienceLevel: _experience,
      cycleStatus: _cycle,
      day90GoalText: _goalText.text.trim(),
      photoTrackingType: _photoType,
      // A retake keeps her settings.
      sundayPhotoPromptEnabled: repo.profile?.sundayPhotoPromptEnabled ?? true,
      remindersOn: repo.profile?.remindersOn ?? true,
      reminderMinutes: repo.profile?.reminderMinutes ?? 9 * 60,
      lockWithFaceId: repo.profile?.lockWithFaceId ?? false,
      proteinTargetG: repo.profile?.proteinTargetG,
      createdAt: repo.profile?.createdAt ?? DateTime.now(),
    );
    if (!_isRetake) {
      // Spec: the plans come right after the protocol screen, before the app.
      await Navigator.push(context, SlidePageRoute(page: const PaywallView()));
    }
    await repo.completeOnboarding(profile, _compoundNames);
    widget.onFinished?.call();
  }

  Future<void> _skipAll() async {
    HapticFeedback.lightImpact();
    await context.read<ProtocolRepository>().completeOnboarding(UserProfile(createdAt: DateTime.now()), const []);
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    return AnimatedSwitcher(
      duration: Duration(milliseconds: reduceMotion ? 0 : 500),
      switchInCurve: Curves.easeOutCubic,
      child: _step == _steps
          ? _Summary(
              key: const ValueKey('summary'),
              compounds: _compoundNames,
              goals: _goals,
              isRetake: _isRetake,
              onBack: _back,
              onContinue: _next,
            )
          : _questions(reduceMotion),
    );
  }

  Widget _questions(bool reduceMotion) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: _step > 0 || _isRetake
            ? IconButton(
                tooltip: 'Back',
                icon: const HugeIcon(icon: HugeIcons.strokeRoundedArrowLeft01, color: OmnyaColors.charcoal, size: 22),
                onPressed: _back,
              )
            : const Center(child: OmnyaLogo(size: 28)),
        centerTitle: true,
        title: _step < _steps
            ? Text('${_step + 1} of $_steps', style: OmnyaTypography.tag(color: OmnyaColors.taupeDark))
            : null,
        actions: [
          if (!_isRetake && _step < _steps)
            TextButton(
              onPressed: _skipAll,
              child: Text('Skip', style: OmnyaTypography.label(color: OmnyaColors.taupeDark)),
            ),
          const SizedBox(width: 8),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: TweenAnimationBuilder<double>(
                duration: Duration(milliseconds: reduceMotion ? 0 : 450),
                curve: Curves.easeOutCubic,
                tween: Tween(end: (_step + 1).clamp(1, _steps) / _steps),
                builder: (_, value, _) => LinearProgressIndicator(
                  value: value,
                  minHeight: 3,
                  backgroundColor: OmnyaColors.sandMuted,
                  color: OmnyaColors.plum,
                ),
              ),
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: Duration(milliseconds: reduceMotion ? 0 : 320),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween(begin: const Offset(0.04, 0), end: Offset.zero).animate(animation),
                          child: child,
                        ),
                      ),
                      child: KeyedSubtree(key: ValueKey(_step), child: _buildStep()),
                    ),
                  ),
                  TactileButton(
                    label: switch (_step) {
                      4 when _goalText.text.trim().isEmpty => 'Skip this one',
                      _ => 'Continue',
                    },
                    width: double.infinity,
                    onPressed: _answered ? _next : null,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStep() => switch (_step) {
    0 => _Question(
      title: 'What are you here for?',
      hint: 'Pick as many as you like.',
      children: [
        for (final g in const ['Snatched', 'Glow', 'Heal and recover', 'Energy', 'All of it'])
          _Option(
            title: g,
            selected: _goals.contains(g),
            onTap: () => setState(() {
              if (g == 'All of it') {
                _goals
                  ..clear()
                  ..add(g);
              } else {
                _goals.remove('All of it');
                _goals.contains(g) ? _goals.remove(g) : _goals.add(g);
              }
            }),
          ),
      ],
    ),
    1 => _Question(
      title: 'What are you running, or thinking about?',
      hint: "You'll add your own dose and schedule after.",
      children: [
        for (final name in const ['Retatrutide', 'GHK-Cu', 'KLOW'])
          _Option(
            title: name,
            subtitle: CompoundDirectory.find(name)?.nickname,
            selected: _compounds.contains(name),
            onTap: () => setState(() {
              _compounds.remove('Not sure yet');
              _compounds.contains(name) ? _compounds.remove(name) : _compounds.add(name);
            }),
          ),
        _Option(
          title: 'Not sure yet',
          subtitle: 'Add compounds any time from Stack',
          selected: _compounds.contains('Not sure yet'),
          onTap: () => setState(() {
            _compounds
              ..clear()
              ..add('Not sure yet');
          }),
        ),
      ],
    ),
    2 => _Question(
      title: 'How far in are you?',
      hint: 'This sets the tone of your first insights.',
      children: [
        for (final l in const ["Haven't started", 'First month', 'A few months', 'Over a year'])
          _Option(title: l, selected: _experience == l, onTap: () => setState(() => _experience = l)),
      ],
    ),
    3 => _Question(
      title: 'Do you get a period?',
      hint: 'Turns on cycle tracking, so water weight gets flagged instead of worrying you.',
      children: [
        for (final (value, label) in const [
          ('yes', 'Yes'),
          ('no', 'No'),
          ('irregular', 'Irregular'),
          ('birth_control', 'On birth control'),
        ])
          _Option(title: label, selected: _cycle == value, onTap: () => setState(() => _cycle = value)),
      ],
    ),
    4 => _Question(
      title: 'What would make this worth it in 90 days?',
      hint: "One line, in your words. We'll show it back to you on day 30 and day 90.",
      children: [
        TextField(
          controller: _goalText,
          maxLines: 3,
          maxLength: 200,
          textCapitalization: TextCapitalization.sentences,
          onChanged: (_) => setState(() {}),
          style: OmnyaTypography.bodyLarge(),
          decoration: InputDecoration(
            hintText: 'Type your answer',
            hintStyle: OmnyaTypography.bodyLarge(color: OmnyaColors.charcoalLight),
            filled: true,
            fillColor: OmnyaColors.cream,
            contentPadding: const EdgeInsets.all(16),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(OmnyaRadius.control),
              borderSide: const BorderSide(color: OmnyaColors.taupe),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(OmnyaRadius.control),
              borderSide: const BorderSide(color: OmnyaColors.plum, width: 1.5),
            ),
          ),
        ),
      ],
    ),
    5 => _Question(
      title: 'Photos: face, body, or both?',
      hint: 'One photo a week, compared with the last. They stay on your phone.',
      children: [
        for (final (value, label) in const [('face', 'Face'), ('body', 'Body'), ('both', 'Both')])
          _Option(title: label, selected: _photoType == value, onTap: () => setState(() => _photoType = value)),
      ],
    ),
    _ => const SizedBox.shrink(),
  };
}

class _Question extends StatelessWidget {
  final String title;
  final String hint;
  final List<Widget> children;
  const _Question({required this.title, required this.hint, required this.children});

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        Text(title, style: OmnyaTypography.displayMedium()),
        const SizedBox(height: 8),
        Text(hint, style: OmnyaTypography.bodyMedium()),
        const SizedBox(height: 24),
        ...children,
      ],
    );
  }
}

class _Option extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;
  const _Option({required this.title, this.subtitle, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Semantics(
        button: true,
        selected: selected,
        child: GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            decoration: BoxDecoration(
              color: selected ? OmnyaColors.plumSubtle : OmnyaColors.cream,
              borderRadius: BorderRadius.circular(OmnyaRadius.control),
              // Same border width in both states, so selecting never shifts the layout.
              border: Border.all(color: selected ? OmnyaColors.plum : OmnyaColors.taupe, width: 1.5),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: OmnyaTypography.label(weight: FontWeight.w600)),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(subtitle!, style: OmnyaTypography.bodySmall()),
                      ],
                    ],
                  ),
                ),
                SizedBox.square(
                  dimension: 24,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    transitionBuilder: (child, a) => ScaleTransition(scale: a, child: child),
                    child: selected
                        ? const HugeIcon(
                            key: ValueKey(true),
                            icon: HugeIcons.strokeRoundedCheckmarkCircle03,
                            color: OmnyaColors.plum,
                            size: 24,
                          )
                        : Container(
                            key: const ValueKey(false),
                            margin: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: OmnyaColors.taupe, width: 1.5),
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The end of the quiz, full screen like the Day 1 moment.
class _Summary extends StatelessWidget {
  final List<String> compounds;
  final Set<String> goals;
  final bool isRetake;
  final VoidCallback onBack;
  final VoidCallback onContinue;
  const _Summary({
    super.key,
    required this.compounds,
    required this.goals,
    required this.isRetake,
    required this.onBack,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    final ghkForGlow = compounds.contains('GHK-Cu') && (goals.contains('Glow') || goals.contains('All of it'));
    final muted = OmnyaColors.sandMuted.withValues(alpha: 0.75);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: OmnyaColors.plum,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 28, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconButton(
                  tooltip: 'Back',
                  icon: const HugeIcon(icon: HugeIcons.strokeRoundedArrowLeft01, color: OmnyaColors.cream, size: 22),
                  onPressed: onBack,
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.only(left: 16, top: 48),
                    children: [
                      Rise(
                        delay: 0,
                        child: Text(
                          'Your protocol is ready.',
                          style: OmnyaTypography.displayLarge(
                            color: OmnyaColors.cream,
                          ).copyWith(fontSize: 48, height: 1.05),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Rise(
                        delay: 0.15,
                        child: Text(
                          ghkForGlow
                              ? "Women running GHK-Cu for glow usually see skin changes around week 4. Let's track yours."
                              : 'Log each dose and check in daily. Your first pattern shows up within two weeks.',
                          style: OmnyaTypography.bodyLarge(color: OmnyaColors.sandMuted),
                        ),
                      ),
                      if (compounds.isNotEmpty) ...[
                        const SizedBox(height: 36),
                        Rise(
                          delay: 0.3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('In your stack', style: OmnyaTypography.label(color: muted)),
                              const SizedBox(height: 8),
                              for (final c in compounds)
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                  child: Text(c, style: OmnyaTypography.headline(color: OmnyaColors.cream)),
                                ),
                              const SizedBox(height: 6),
                              Text(
                                'Add your dose and schedule for each from Today or Stack.',
                                style: OmnyaTypography.bodySmall(color: muted),
                              ),
                            ],
                          ),
                        ),
                      ],
                      // Spec page 7: the widget is on her home screen before she closes the app.
                      if (!isRetake && defaultTargetPlatform == TargetPlatform.iOS) ...[
                        const SizedBox(height: 36),
                        Rise(
                          delay: 0.4,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Put your next dose on your home screen',
                                style: OmnyaTypography.label(color: OmnyaColors.cream, weight: FontWeight.w600),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Touch and hold your home screen, tap Edit, then Add Widget, and choose Omnya.',
                                style: OmnyaTypography.bodySmall(color: muted),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 36),
                      Rise(
                        delay: 0.45,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Photos stay on your phone. No account needed.',
                              style: OmnyaTypography.label(color: OmnyaColors.cream, weight: FontWeight.w600),
                            ),
                            const SizedBox(height: 8),
                            Text(AppCopy.medicalDisclaimer, style: OmnyaTypography.bodySmall(color: muted)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 16, top: 12),
                  child: TactileButton(
                    label: isRetake ? 'Save my answers' : 'Continue',
                    variant: TactileButtonVariant.onDark,
                    width: double.infinity,
                    onPressed: onContinue,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
