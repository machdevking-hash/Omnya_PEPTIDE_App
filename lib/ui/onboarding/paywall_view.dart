import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:provider/provider.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/constants/app_copy.dart';
import '../../core/theme/omnya_colors.dart';
import '../../core/theme/omnya_typography.dart';
import '../../core/widgets/omnya_card.dart';
import '../../core/widgets/omnya_controls.dart';
import '../../core/widgets/omnya_pro_badge.dart';
import '../../core/widgets/omnya_toast.dart';
import '../../core/widgets/slide_page_route.dart';
import '../../core/widgets/tactile_button.dart';
import '../../data/services/subscription_service.dart';

Future<void> openPaywall(BuildContext context) => Navigator.push(context, SlidePageRoute(page: const PaywallView()));

/// Pro content. Pro sees [child]; free sees it blurred, and a tap opens the plans (spec page 8).
class ProGate extends StatelessWidget {
  final String message;
  final Widget child;
  const ProGate({super.key, required this.message, required this.child});

  @override
  Widget build(BuildContext context) {
    if (context.watch<SubscriptionService>().isPro) return child;
    return Semantics(
      button: true,
      label: message,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.lightImpact();
          openPaywall(context);
        },
        child: BlurredPreview(message: message, child: child),
      ),
    );
  }
}

/// Plans from spec page 8. Backed by RevenueCat StoreKit subscriptions.
class PaywallView extends StatefulWidget {
  const PaywallView({super.key});

  @override
  State<PaywallView> createState() => _PaywallViewState();
}

class _PaywallViewState extends State<PaywallView> {
  int _plan = 1; // yearly is shown first (spec)

  static const _pro = [
    'Unlimited compounds',
    'What changed since each compound started',
    'Weekly photo read and trend scores',
    'Cycle-aware weight insights',
    'Full weekly report and doctor PDF',
    'Watermark-free progress cards',
    'Circles',
    'Monthly spend across your stack',
  ];

  static const _free = [
    'Mixing calculator',
    'Up to 2 compounds',
    'Weight and daily check-ins',
    'Widget and Live Activity',
    'Weekly report headline',
  ];

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _handlePurchase(SubscriptionService sub, List<_PlanUiData> plans) async {
    if (plans.isEmpty || _plan >= plans.length) return;
    final selected = plans[_plan];
    if (selected.package == null) {
      await sub.fetchOfferings();
      if (!mounted || sub.offerings?.current != null) return;
      OmnyaToast.show(
        context,
        title: "Couldn't reach the App Store",
        message: 'Check your connection and try again.',
        type: OmnyaToastType.error,
      );
      return;
    }

    HapticFeedback.lightImpact();
    final outcome = await sub.purchase(selected.package!);
    if (!mounted) return;
    switch (outcome) {
      case PurchaseOutcome.success:
        OmnyaToast.show(context, title: 'Welcome to Omnya Pro', type: OmnyaToastType.success);
        Navigator.pop(context);
      case PurchaseOutcome.failed:
        OmnyaToast.show(
          context,
          title: "That didn't go through",
          message: "You weren't charged. Try again in a moment.",
          type: OmnyaToastType.error,
        );
      case PurchaseOutcome.cancelled:
        break;
    }
  }

  Future<void> _handleRestore(SubscriptionService sub) async {
    HapticFeedback.lightImpact();
    final isPro = await sub.restore();
    if (!mounted) return;
    if (isPro) {
      OmnyaToast.show(
        context,
        title: 'Purchases restored',
        message: 'You have Pro access.',
        type: OmnyaToastType.success,
      );
      Navigator.pop(context);
    } else {
      OmnyaToast.show(
        context,
        title: 'No active Pro found',
        message: 'No previous subscriptions were found for this Apple ID.',
        type: OmnyaToastType.info,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final sub = context.watch<SubscriptionService>();
    final currentOffering = sub.offerings?.current;

    Package? monthlyPkg;
    Package? yearlyPkg;
    Package? lifetimePkg;

    if (currentOffering != null) {
      monthlyPkg = currentOffering.monthly;
      yearlyPkg = currentOffering.annual;
      lifetimePkg = currentOffering.lifetime;
    }

    // Prices only ever come from the App Store, in her currency.
    final trial = sub.trialEligible(yearlyPkg);
    final plans = [
      _PlanUiData(
        name: 'Monthly',
        price: monthlyPkg?.storeProduct.priceString ?? '–',
        note: 'per month',
        package: monthlyPkg,
      ),
      _PlanUiData(
        name: 'Yearly',
        price: yearlyPkg?.storeProduct.priceString ?? '–',
        note: trial ? 'per year, 7-day trial' : 'per year',
        package: yearlyPkg,
      ),
      _PlanUiData(
        name: 'Lifetime',
        price: lifetimePkg?.storeProduct.priceString ?? '–',
        note: 'one time',
        package: lifetimePkg,
      ),
    ];
    final selected = plans[_plan];

    final isAlreadyPro = sub.isPro;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Close',
          icon: const HugeIcon(icon: HugeIcons.strokeRoundedCancel01, color: OmnyaColors.charcoal, size: 22),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          TextButton(
            onPressed: sub.isLoading ? null : () => _handleRestore(sub),
            child: Text(
              'Restore',
              style: OmnyaTypography.label(color: OmnyaColors.taupeDark, weight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 20),
          children: [
            Text('Free users log.\nPro users learn.', style: OmnyaTypography.displayLarge()),
            const SizedBox(height: 20),
            Row(
              children: [
                for (var i = 0; i < plans.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(
                    child: _PlanCard(plan: plans[i], selected: _plan == i, onTap: () => setState(() => _plan = i)),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 20),
            OmnyaCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          isAlreadyPro ? 'Pro (Active)' : 'Pro',
                          style: OmnyaTypography.label(weight: FontWeight.w600),
                        ),
                      ),
                      const OmnyaProBadge(),
                    ],
                  ),
                  const SizedBox(height: 10),
                  for (final f in _pro) _Feature(f),
                  const Divider(height: 28),
                  Text('Free', style: OmnyaTypography.label(weight: FontWeight.w600)),
                  const SizedBox(height: 10),
                  for (final f in _free) _Feature(f, muted: true),
                ],
              ),
            ),
            const SizedBox(height: 24),
            TactileButton(
              label: isAlreadyPro
                  ? 'You already have Pro'
                  : selected.package == null
                  ? 'Try again'
                  : (_plan == 1 && trial ? 'Start 7-day free trial' : 'Upgrade to Pro'),
              width: double.infinity,
              isLoading: sub.isLoading,
              onPressed: isAlreadyPro || sub.isLoading ? null : () => _handlePurchase(sub, plans),
            ),
            const SizedBox(height: 10),
            Text(
              selected.package == null
                  ? "Plans couldn't load. Check your connection."
                  : _plan == 2
                  ? 'One payment. No subscription.'
                  : [
                      if (_plan == 1 && trial) '7-day free trial, then ${selected.price} a year.',
                      'Renews automatically unless cancelled at least 24 hours before the period ends. '
                          'Manage or cancel in your App Store settings.',
                    ].join(' '),
              textAlign: TextAlign.center,
              style: OmnyaTypography.bodySmall(),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                GestureDetector(
                  onTap: () => _openUrl(AppCopy.termsOfServiceUrl),
                  child: Text(
                    'Terms of Use (EULA)',
                    style: OmnyaTypography.bodySmall(
                      color: OmnyaColors.taupeDark,
                    ).copyWith(decoration: TextDecoration.underline),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text('·', style: OmnyaTypography.bodySmall(color: OmnyaColors.taupeDark)),
                ),
                GestureDetector(
                  onTap: () => _openUrl(AppCopy.privacyPolicyUrl),
                  child: Text(
                    'Privacy Policy',
                    style: OmnyaTypography.bodySmall(
                      color: OmnyaColors.taupeDark,
                    ).copyWith(decoration: TextDecoration.underline),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () {
                HapticFeedback.lightImpact();
                Navigator.pop(context);
              },
              child: Text(
                'Continue',
                style: OmnyaTypography.label(color: OmnyaColors.plum, weight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlanUiData {
  final String name;
  final String price;
  final String note;
  final Package? package;

  const _PlanUiData({required this.name, required this.price, required this.note, this.package});
}

class _PlanCard extends StatelessWidget {
  final _PlanUiData plan;
  final bool selected;
  final VoidCallback onTap;
  const _PlanCard({required this.plan, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
          decoration: BoxDecoration(
            color: selected ? OmnyaColors.plumSubtle : OmnyaColors.cream,
            borderRadius: BorderRadius.circular(OmnyaRadius.control),
            border: Border.all(color: selected ? OmnyaColors.plum : OmnyaColors.line, width: 1.5),
          ),
          child: Column(
            children: [
              Text(plan.name, style: OmnyaTypography.tag(color: OmnyaColors.taupeDark)),
              const SizedBox(height: 4),
              Text(
                plan.price,
                style: OmnyaTypography.headline(color: selected ? OmnyaColors.plum : OmnyaColors.charcoal),
              ),
              const SizedBox(height: 2),
              Text(plan.note, textAlign: TextAlign.center, style: OmnyaTypography.bodySmall()),
            ],
          ),
        ),
      ),
    );
  }
}

class _Feature extends StatelessWidget {
  final String text;
  final bool muted;
  const _Feature(this.text, {this.muted = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          HugeIcon(
            icon: HugeIcons.strokeRoundedCheckmarkBadge03,
            color: muted ? OmnyaColors.taupeDark : OmnyaColors.plum,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: OmnyaTypography.bodyMedium(color: OmnyaColors.charcoal)),
          ),
        ],
      ),
    );
  }
}
