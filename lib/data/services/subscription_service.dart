import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'local_storage_service.dart';

enum PurchaseOutcome { success, cancelled, failed }

/// Manages RevenueCat StoreKit subscriptions and Pro entitlements.
class SubscriptionService extends ChangeNotifier {
  static const entitlementPro = 'pro';

  // Passed with --dart-define=REVENUECAT_APPLE_API_KEY=appl_... on release builds.
  static const _appleApiKey = String.fromEnvironment('REVENUECAT_APPLE_API_KEY');

  final LocalStorageService _storage;
  bool _isPro;
  Offerings? _offerings;
  bool _initialized = false;
  bool _isLoading = false;
  final _trialEligible = <String>{};

  SubscriptionService({required LocalStorageService storage}) : _storage = storage, _isPro = storage.getIsPro();

  bool get isPro => _isPro;
  Offerings? get offerings => _offerings;
  bool get isInitialized => _initialized;
  bool get isLoading => _isLoading;

  /// True only when the App Store says she can still get this product's free trial.
  /// Unknown counts as no, so the paywall never promises a trial she won't get.
  bool trialEligible(Package? p) =>
      p != null && p.storeProduct.introductoryPrice != null && _trialEligible.contains(p.storeProduct.identifier);

  /// Initializes RevenueCat with Apple API key and listens for customer updates.
  Future<void> init({String? userId}) async {
    if (_initialized) return;
    if (_appleApiKey.isEmpty) {
      debugPrint('RevenueCat skipped: build with --dart-define=REVENUECAT_APPLE_API_KEY=appl_...');
      return;
    }

    try {
      final config = PurchasesConfiguration(_appleApiKey);
      if (userId != null && userId.isNotEmpty) {
        config.appUserID = userId;
      }
      await Purchases.configure(config);
      _initialized = true;

      Purchases.addCustomerInfoUpdateListener(_updateEntitlements);

      final info = await Purchases.getCustomerInfo();
      _updateEntitlements(info);
      await fetchOfferings();
    } catch (e) {
      debugPrint('RevenueCat initialization skipped or offline: $e');
    }
  }

  /// Identifies the customer with their authenticated user ID (e.g. Supabase UID).
  Future<void> identify(String userId) async {
    if (!_initialized) return;
    try {
      final info = await Purchases.logIn(userId);
      _updateEntitlements(info.customerInfo);
    } catch (e) {
      debugPrint('RevenueCat logIn failed: $e');
    }
  }

  /// Signs out of the RevenueCat identity on data deletion/logout.
  Future<void> reset() async {
    _isPro = false;
    await _storage.saveIsPro(false);
    notifyListeners();
    if (!_initialized) return;
    try {
      final info = await Purchases.logOut();
      _updateEntitlements(info);
    } catch (e) {
      debugPrint('RevenueCat logOut failed: $e');
    }
  }

  /// Loads current offerings and packages configured in RevenueCat dashboard.
  Future<void> fetchOfferings() async {
    if (!_initialized) return init();
    try {
      _offerings = await Purchases.getOfferings();
      final products = [for (final p in _offerings?.current?.availablePackages ?? <Package>[]) p.storeProduct];
      final withTrial = [
        for (final p in products)
          if (p.introductoryPrice != null) p.identifier,
      ];
      _trialEligible.clear();
      if (withTrial.isNotEmpty) {
        final status = await Purchases.checkTrialOrIntroductoryPriceEligibility(withTrial);
        _trialEligible.addAll([
          for (final e in status.entries)
            if (e.value.status == IntroEligibilityStatus.introEligibilityStatusEligible) e.key,
        ]);
      }
      notifyListeners();
    } catch (e) {
      debugPrint('RevenueCat fetchOfferings failed: $e');
    }
  }

  /// Purchases a selected package (monthly, yearly, lifetime).
  Future<PurchaseOutcome> purchase(Package package) async {
    _isLoading = true;
    notifyListeners();
    try {
      final result = await Purchases.purchase(PurchaseParams.package(package));
      _updateEntitlements(result.customerInfo);
      return _isPro ? PurchaseOutcome.success : PurchaseOutcome.failed;
    } on PlatformException catch (e) {
      if (PurchasesErrorHelper.getErrorCode(e) == PurchasesErrorCode.purchaseCancelledError) {
        return PurchaseOutcome.cancelled;
      }
      debugPrint('Purchase error: $e');
      return PurchaseOutcome.failed;
    } catch (e) {
      debugPrint('Purchase error: $e');
      return PurchaseOutcome.failed;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Restores previous purchases according to App Store guidelines.
  Future<bool> restore() async {
    if (!_initialized) await init();
    _isLoading = true;
    notifyListeners();
    try {
      final customerInfo = await Purchases.restorePurchases();
      _updateEntitlements(customerInfo);
      return _isPro;
    } catch (e) {
      debugPrint('Restore error: $e');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void _updateEntitlements(CustomerInfo info) {
    final hasPro = info.entitlements.all[entitlementPro]?.isActive ?? false;
    if (_isPro != hasPro) {
      _isPro = hasPro;
      _storage.saveIsPro(hasPro);
      notifyListeners();
    }
  }
}
