import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:provider/provider.dart';
import '../../core/constants/compound_directory.dart';
import '../../core/theme/omnya_colors.dart';
import '../../core/theme/omnya_typography.dart';
import '../../core/widgets/omnya_card.dart';
import '../../core/widgets/omnya_controls.dart';
import '../../core/widgets/slide_page_route.dart';
import '../../core/widgets/tactile_button.dart';
import '../../data/models/compound.dart';
import '../../data/repositories/protocol_repository.dart';
import '../../data/services/reminder_service.dart';
import '../../data/services/subscription_service.dart';
import '../../domain/schedule.dart';
import '../features/circle/circle_view.dart';
import '../features/photo_read/weekly_photo_view.dart';
import '../features/progress/progress_view.dart';
import '../features/progress/weekly_report_view.dart';
import '../features/stack/compound_editor_sheet.dart';
import '../features/stack/stack_view.dart';
import '../features/today/dose_logging.dart';
import '../features/today/today_view.dart';
import '../onboarding/paywall_view.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

/// Lets the shell know when a full-screen page covers it.
final shellRoutes = RouteObserver<PageRoute<dynamic>>();

class _MainShellState extends State<MainShell> with RouteAware {
  // Native views still take touches under a covering page, so the bar is removed while covered.
  bool _covered = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) shellRoutes.subscribe(this, route);
  }

  @override
  void didPushNext() => setState(() => _covered = true);

  @override
  void didPopNext() => setState(() => _covered = false);

  int _index = 0;

  static const _tabs = [
    (label: 'Today', asset: 'today'),
    (label: 'Progress', asset: 'progress'),
    (label: 'Stack', asset: 'stack'),
    (label: 'Circle', asset: 'circle'),
  ];

  static const _pages = [TodayView(), ProgressView(), StackView(), CircleView()];

  StreamSubscription<String>? _taps;

  @override
  void initState() {
    super.initState();
    // A tapped reminder opens where it points.
    _taps = context.read<ReminderService?>()?.taps.listen((route) {
      if (!mounted) return;
      Navigator.of(context).popUntil((r) => r.isFirst);
      switch (route) {
        case 'week':
          Navigator.push(context, SlidePageRoute(page: const WeeklyReportView()));
        case 'photo':
          Navigator.push(context, SlidePageRoute(page: const WeeklyPhotoView()));
        case 'progress':
          setState(() => _index = 1);
          if (!context.read<SubscriptionService>().isPro) openPaywall(context);
        default:
          setState(() => _index = 0);
      }
    });
  }

  @override
  void dispose() {
    _taps?.cancel();
    shellRoutes.unsubscribe(this);
    super.dispose();
  }

  void _select(int i) {
    if (i == _index) return;
    HapticFeedback.selectionClick();
    setState(() => _index = i);
  }

  @override
  Widget build(BuildContext context) {
    // The bar steps aside while typing so it never covers a focused field.
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    return Scaffold(
      body: Stack(
        children: [
          SafeArea(
            bottom: false,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 540),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, a) => FadeTransition(opacity: a, child: child),
                  child: KeyedSubtree(key: ValueKey(_index), child: _pages[_index]),
                ),
              ),
            ),
          ),
          if (!keyboardOpen && !_covered)
            Positioned(
              left: 0,
              right: 0,
              // Clear of the home indicator, with a little air.
              bottom: MediaQuery.viewPaddingOf(context).bottom.clamp(16, 40) + 4,
              child: _tabBar(),
            ),
        ],
      ),
    );
  }

  void _openQuickLog() {
    HapticFeedback.mediumImpact();
    showOmnyaSheet<void>(context, builder: (_) => _QuickLogSheet(shellContext: context));
  }

  /// A row of round Liquid Glass buttons, icons only: the four pages, then one that logs a dose.
  /// Native glass draws above Flutter, so the row steps aside while a sheet is up.
  Widget _tabBar() {
    // Five across with 12pt gaps; shrinks on the narrowest phones.
    final size = ((MediaQuery.sizeOf(context).width - 32 - 4 * 12) / 5).clamp(44.0, 58.0);
    Widget circle({required String label, required String icon, bool selected = false, required VoidCallback onTap}) {
      final assetPath = 'assets/icons/$icon${selected ? '_active' : ''}.svg';
      final color = selected ? OmnyaColors.plum : OmnyaColors.taupeDark;

      if (PlatformVersion.shouldUseNativeGlass) {
        return Semantics(
          button: true,
          selected: selected,
          label: label,
          excludeSemantics: true,
          child: CNButton.icon(
            key: ValueKey(icon),
            imageAsset: CNImageAsset(assetPath, size: 26, color: color),
            onPressed: onTap,
            config: CNButtonConfig(style: CNButtonStyle.glass, width: size, minHeight: size),
          ),
        );
      }

      return _FlutterGlassTabButton(
        key: ValueKey(icon),
        label: label,
        assetPath: assetPath,
        selected: selected,
        size: size,
        color: color,
        onTap: onTap,
      );
    }

    return ValueListenableBuilder<int>(
      valueListenable: CNTabBarRouteObserver.anyModalDepth,
      builder: (_, depth, _) => depth > 0
          ? SizedBox(height: size)
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              spacing: 12,
              children: [
                for (final (i, t) in _tabs.indexed)
                  circle(label: t.label, icon: t.asset, selected: i == _index, onTap: () => _select(i)),
                circle(label: 'Log a dose', icon: 'add', onTap: _openQuickLog),
              ],
            ),
    );
  }
}

/// Every compound in her stack, one tap from logging.
class _QuickLogSheet extends StatefulWidget {
  /// Stays mounted after the sheet closes; the milestone and Undo toast show from it.
  final BuildContext shellContext;
  const _QuickLogSheet({required this.shellContext});

  @override
  State<_QuickLogSheet> createState() => _QuickLogSheetState();
}

class _QuickLogSheetState extends State<_QuickLogSheet> {
  String _filter = '';

  Future<void> _confirmAndLog(Compound c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Log ${CompoundDirectory.shortName(c.name)}, ${formatDose(c.doseOn(DateTime.now()), c.unit)}?',
          style: OmnyaTypography.headline(),
        ),
        content: c.isInjected ? Text('Site: ${c.nextSite}', style: OmnyaTypography.bodyMedium()) : null,
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Log it',
              style: OmnyaTypography.label(color: OmnyaColors.plum, weight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    Navigator.pop(context);
    final shell = widget.shellContext;
    if (shell.mounted) await logDoseWithFeedback(shell, c);
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<ProtocolRepository>();
    final now = DateTime.now();
    final all = repo.compounds;
    final shown = all.where((c) => _filter.isEmpty || c.name.toLowerCase().contains(_filter)).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Log a dose', style: OmnyaTypography.headline()),
        const SizedBox(height: 14),
        if (all.length > 4) ...[
          TextField(
            onChanged: (v) => setState(() => _filter = v.trim().toLowerCase()),
            style: OmnyaTypography.bodyLarge(),
            decoration: InputDecoration(
              hintText: 'Search your stack',
              hintStyle: OmnyaTypography.bodyLarge(color: OmnyaColors.charcoalLight),
              prefixIcon: const Padding(
                padding: EdgeInsets.all(12),
                child: HugeIcon(icon: HugeIcons.strokeRoundedSearch01, color: OmnyaColors.charcoalLight, size: 20),
              ),
              filled: true,
              fillColor: OmnyaColors.sand,
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(OmnyaRadius.control),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (all.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: OmnyaEmptyState(
              title: 'Nothing to log yet',
              body: 'Add what you take and it shows up here.',
              action: TactileButton(
                label: 'Add a compound',
                onPressed: () {
                  Navigator.pop(context);
                  showCompoundEditor(widget.shellContext);
                },
              ),
            ),
          )
        else if (shown.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              'Nothing in your stack matches that.',
              textAlign: TextAlign.center,
              style: OmnyaTypography.bodyMedium(),
            ),
          )
        else
          for (final c in shown)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: OmnyaCard(
                padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
                color: OmnyaColors.sand,
                onTap: () => c.isConfigured ? _confirmAndLog(c) : _setUp(c),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(c.name, style: OmnyaTypography.label(weight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          Text(
                            c.isConfigured
                                ? '${nextDoseLabel(c, repo.doseLogs)} · ${dueLine(c, repo.doseLogs, now)}'
                                : 'Add dose and schedule first',
                            style: OmnyaTypography.bodySmall(),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        c.isConfigured ? 'Log' : 'Set up',
                        style: OmnyaTypography.label(color: OmnyaColors.plum, weight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
            ),
      ],
    );
  }

  void _setUp(Compound c) {
    Navigator.pop(context);
    showCompoundEditor(widget.shellContext, compound: c);
  }
}

/// Fallback tab button for non-native-glass platforms (such as Android) that
/// displays the true SVG icons with a tactile frosted-glass circle effect.
class _FlutterGlassTabButton extends StatefulWidget {
  final String label;
  final String assetPath;
  final bool selected;
  final double size;
  final Color color;
  final VoidCallback onTap;

  const _FlutterGlassTabButton({
    super.key,
    required this.label,
    required this.assetPath,
    required this.selected,
    required this.size,
    required this.color,
    required this.onTap,
  });

  @override
  State<_FlutterGlassTabButton> createState() => _FlutterGlassTabButtonState();
}

class _FlutterGlassTabButtonState extends State<_FlutterGlassTabButton> with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 100),
    reverseDuration: const Duration(milliseconds: 140),
  );
  late final Animation<double> _scale = Tween<double>(
    begin: 1.0,
    end: 0.94,
  ).animate(CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic));

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: widget.selected,
      label: widget.label,
      excludeSemantics: true,
      child: ScaleTransition(
        scale: _scale,
        child: GestureDetector(
          onTapDown: (_) {
            HapticFeedback.lightImpact();
            _anim.forward();
          },
          onTapUp: (_) {
            _anim.reverse();
            widget.onTap();
          },
          onTapCancel: () => _anim.reverse(),
          behavior: HitTestBehavior.opaque,
          child: ClipOval(
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: Container(
                width: widget.size,
                height: widget.size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.selected
                      ? OmnyaColors.cream.withValues(alpha: 0.94)
                      : OmnyaColors.cream.withValues(alpha: 0.78),
                  border: Border.all(
                    color: widget.selected
                        ? OmnyaColors.plum.withValues(alpha: 0.3)
                        : OmnyaColors.taupe.withValues(alpha: 0.35),
                    width: 1.0,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: OmnyaColors.charcoal.withValues(alpha: 0.08),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Center(
                  child: SvgPicture.asset(
                    widget.assetPath,
                    width: 26,
                    height: 26,
                    colorFilter: ColorFilter.mode(widget.color, BlendMode.srcIn),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
