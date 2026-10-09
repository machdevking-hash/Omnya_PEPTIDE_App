import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../../core/constants/compound_directory.dart';
import '../../domain/insights.dart';
import '../../domain/schedule.dart';
import '../models/circle_data.dart';
import '../models/compound.dart';
import '../models/daily_check_in.dart';
import '../models/dose_log.dart';
import '../models/progress_photo.dart';
import '../models/user_profile.dart';
import '../services/cloud_service.dart';
import '../services/local_storage_service.dart';
import '../services/native_service.dart';
import '../services/shotsy_import.dart';

/// App state. Every change lands on the device first, then syncs in the background.
class ProtocolRepository extends ChangeNotifier {
  final LocalStorageService storage;
  final CloudService cloud;
  final _uuid = const Uuid();

  List<Compound> _compounds;
  List<DoseLog> _doseLogs;
  List<DailyCheckIn> _checkIns;
  List<ProgressPhoto> _photos;
  UserProfile? _profile;
  Circle? _circle;

  bool _isSyncing = false;
  bool _syncAgain = false;
  String? _syncError;
  Timer? _syncDebounce;

  ProtocolRepository({required this.storage, required this.cloud})
    : _compounds = storage.getCompounds(),
      _doseLogs = storage.getDoseLogs()..sort((a, b) => b.timestamp.compareTo(a.timestamp)),
      _checkIns = storage.getCheckIns()..sort((a, b) => b.date.compareTo(a.date)),
      _photos = storage.getPhotos()..sort((a, b) => a.takenAt.compareTo(b.takenAt)),
      _profile = storage.getProfile(),
      _circle = storage.getCircle() {
    sync();
  }

  List<Compound> get compounds => List.unmodifiable(_compounds);

  /// Newest first.
  List<DoseLog> get doseLogs => List.unmodifiable(_doseLogs);

  /// Newest first.
  List<DailyCheckIn> get checkIns => List.unmodifiable(_checkIns);

  /// Oldest first.
  List<ProgressPhoto> get photos => List.unmodifiable(_photos);
  UserProfile? get profile => _profile;
  Circle? get circle => _circle;
  bool get isSyncing => _isSyncing;
  bool get hasPendingSync => storage.hasPendingSync;
  String? get syncError => _syncError;
  DateTime? get lastSyncTimestamp => storage.lastSyncTimestamp;
  String? get myUserId => cloud.currentUserId;

  // Doses ---------------------------------------------------------------------

  /// Logs the compound's dose at its next site, then moves the site on.
  Future<({DoseLog log, Milestone? milestone})> logDose(String compoundId) async {
    final i = _compounds.indexWhere((c) => c.id == compoundId);
    final c = _compounds[i];
    final now = DateTime.now();
    final log = DoseLog(
      id: _uuid.v4(),
      compoundId: c.id,
      compoundName: c.name,
      dose: c.doseOn(now),
      unit: c.unit,
      injectionSite: c.isInjected ? c.nextSite : '',
      timestamp: now,
    );
    _compounds[i] = c.copyWith(
      nextSite: c.isInjected ? siteAfter(c.nextSite) : c.nextSite,
      dosesLeft: c.dosesLeft == null ? null : () => c.dosesLeft! > 0 ? c.dosesLeft! - 1 : 0,
    );
    _doseLogs.insert(0, log);

    final milestone = milestoneAfterLog(_doseLogs, storage.celebratedMilestones, log.timestamp);
    if (milestone != null) await storage.markMilestone(milestone.name);

    await storage.saveCompounds(_compounds);
    await storage.saveDoseLogs(_doseLogs);
    _changed();
    return (log: log, milestone: milestone);
  }

  /// Takes a dose back out and restores the site and vial count it used.
  Future<void> undoDose(DoseLog log) async {
    _doseLogs.removeWhere((l) => l.id == log.id);
    final i = _compounds.indexWhere((c) => c.id == log.compoundId);
    if (i != -1) {
      final c = _compounds[i];
      _compounds[i] = c.copyWith(
        nextSite: log.injectionSite.isEmpty ? c.nextSite : log.injectionSite,
        dosesLeft: c.dosesLeft == null ? null : () => c.dosesLeft! + 1,
      );
      await storage.saveCompounds(_compounds);
    }
    await storage.saveDoseLogs(_doseLogs);
    await storage.addPendingDelete('dose_logs', log.id);
    _changed();
  }

  // Stack ---------------------------------------------------------------------

  Future<void> saveCompound(Compound compound) async {
    final i = _compounds.indexWhere((c) => c.id == compound.id);
    if (i == -1) {
      _compounds.add(compound);
    } else {
      _compounds[i] = compound;
    }
    await storage.saveCompounds(_compounds);
    _changed();
  }

  /// Her dose history for the compound is kept.
  Future<void> deleteCompound(String id) async {
    _compounds.removeWhere((c) => c.id == id);
    await storage.saveCompounds(_compounds);
    await storage.addPendingDelete('compounds', id);
    _changed();
  }

  Compound newCompound(String name, {DateTime? startDate}) {
    final preset = CompoundDirectory.find(name);
    return Compound(
      id: _uuid.v4(),
      name: preset?.name ?? name.trim(),
      nickname: preset?.nickname ?? '',
      category: preset?.category ?? CompoundCategory.body,
      startDate: dayOf(startDate ?? DateTime.now()),
    );
  }

  // Check-ins -------------------------------------------------------------------

  DailyCheckIn? checkInOn(DateTime day) {
    for (final c in _checkIns) {
      if (sameDay(c.date, day)) return c;
    }
    return null;
  }

  /// One check-in per day: saving again replaces today's.
  Future<void> saveCheckIn({
    required int energy,
    required int appetite,
    double? weightLbs,
    double? waistIn,
    double? sleepHours,
    int? pain,
    List<String> sideEffects = const [],
    int? proteinG,
    int? strength,
    String notes = '',
    bool periodStarted = false,
  }) async {
    final now = DateTime.now();
    final existing = checkInOn(now);
    final entry = DailyCheckIn(
      id: existing?.id ?? _uuid.v4(),
      date: existing?.date ?? now,
      energyLevel: energy,
      appetiteLevel: appetite,
      weightLbs: weightLbs,
      waistIn: waistIn,
      sleepHours: sleepHours,
      pain: pain,
      sideEffects: sideEffects,
      proteinG: proteinG,
      strength: strength,
      notes: notes.trim(),
      periodStarted: periodStarted,
    );
    _checkIns
      ..removeWhere((c) => c.id == entry.id)
      ..insert(0, entry);
    await storage.saveCheckIns(_checkIns);
    _changed();
  }

  // Photos (device only) --------------------------------------------------------

  File photoFile(ProgressPhoto p) => File('${storage.photosDir.path}/${p.fileName}');

  ProgressPhoto? photoInWeekOf(DateTime day) {
    final start = weekStartOf(day);
    final end = addDays(start, 7);
    for (final p in _photos.reversed) {
      if (!p.takenAt.isBefore(start) && p.takenAt.isBefore(end)) return p;
    }
    return null;
  }

  /// Saves this week's photo, replacing one already taken this week.
  Future<void> addPhoto(Uint8List jpeg) async {
    final now = DateTime.now();
    final replaced = photoInWeekOf(now);
    final fileName = '${_uuid.v4()}.jpg';
    final file = File('${storage.photosDir.path}/$fileName');
    await file.writeAsBytes(jpeg, flush: true);
    final score = await NativeService.scorePhoto(file.path);
    final photo = ProgressPhoto(
      id: _uuid.v4(),
      takenAt: now,
      fileName: fileName,
      fullness: score?.fullness,
      evenness: score?.evenness,
    );
    if (replaced != null) {
      _photos.removeWhere((p) => p.id == replaced.id);
      final old = photoFile(replaced);
      if (await old.exists()) await old.delete();
    }
    _photos.add(photo);
    await storage.savePhotos(_photos);
    notifyListeners();
  }

  // Onboarding ------------------------------------------------------------------

  /// Saves her answers and adds the compounds she named. Dose and schedule stay
  /// empty until she enters them: the app never suggests either.
  Future<void> completeOnboarding(UserProfile profile, List<String> compoundNames) async {
    _profile = profile;
    await storage.saveProfile(profile);
    final have = _compounds.map((c) => c.name.toLowerCase()).toSet();
    for (final name in compoundNames) {
      if (!have.contains(name.toLowerCase())) _compounds.add(newCompound(name));
    }
    await storage.saveCompounds(_compounds);
    _changed();
  }

  Future<void> updateSettings(UserProfile profile) async {
    _profile = profile;
    await storage.saveProfile(profile);
    _changed();
  }

  /// Adds doses and weigh-ins from another app's export. Rows already logged are skipped,
  /// so importing the same file twice changes nothing. Returns how many rows were added.
  Future<({int doses, int weights})> importHistory(ImportResult data) async {
    var doses = 0;
    var weights = 0;
    final byName = <String, int>{};
    for (final d in [...data.doses]..sort((a, b) => a.at.compareTo(b.at))) {
      final key = (CompoundDirectory.find(d.compound)?.name ?? d.compound).toLowerCase();
      var i = byName[key] ?? _compounds.indexWhere((c) => c.name.toLowerCase() == key);
      if (i == -1) {
        _compounds.add(newCompound(d.compound, startDate: d.at).copyWith(dose: d.dose, unit: d.unit));
        i = _compounds.length - 1;
      }
      byName[key] = i;
      final c = _compounds[i];
      if (dayOf(d.at).isBefore(c.startDate)) _compounds[i] = c.copyWith(startDate: dayOf(d.at));
      final dup = _doseLogs.any((l) => l.compoundId == c.id && l.timestamp.difference(d.at).inMinutes.abs() < 1);
      if (dup) continue;
      _doseLogs.add(
        DoseLog(
          id: _uuid.v4(),
          compoundId: c.id,
          compoundName: c.name,
          dose: d.dose,
          unit: d.unit,
          injectionSite: d.site,
          timestamp: d.at,
        ),
      );
      doses++;
    }
    for (final w in data.weights) {
      final existing = checkInOn(w.at);
      if (existing?.weightLbs != null) continue;
      _checkIns.removeWhere((c) => c.id == existing?.id);
      _checkIns.add(
        DailyCheckIn(
          id: existing?.id ?? _uuid.v4(),
          date: existing?.date ?? w.at,
          energyLevel: existing?.energyLevel,
          appetiteLevel: existing?.appetiteLevel,
          weightLbs: w.lbs,
          waistIn: existing?.waistIn,
          sleepHours: existing?.sleepHours,
          pain: existing?.pain,
          sideEffects: existing?.sideEffects ?? const [],
          proteinG: existing?.proteinG,
          strength: existing?.strength,
          notes: existing?.notes ?? '',
          periodStarted: existing?.periodStarted ?? false,
        ),
      );
      weights++;
    }
    _doseLogs.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    _checkIns.sort((a, b) => b.date.compareTo(a.date));
    await storage.saveCompounds(_compounds);
    await storage.saveDoseLogs(_doseLogs);
    await storage.saveCheckIns(_checkIns);
    _changed();
    return (doses: doses, weights: weights);
  }

  // Circle ----------------------------------------------------------------------

  Future<void> refreshCircle() async {
    _circle = await cloud.fetchCircle();
    await storage.saveCircle(_circle);
    notifyListeners();
  }

  Future<void> createCircle(String displayName) async {
    _circle = await cloud.createCircle(displayName.trim());
    await _pushMyProgress();
    await refreshCircle();
  }

  Future<void> joinCircle(String code, String displayName) async {
    _circle = await cloud.joinCircle(code.trim().toUpperCase(), displayName.trim());
    await _pushMyProgress();
    await refreshCircle();
  }

  Future<void> leaveCircle() async {
    await cloud.leaveCircle();
    _circle = null;
    await storage.saveCircle(null);
    notifyListeners();
  }

  Future<void> _pushMyProgress() async {
    if (_circle == null) return;
    final now = DateTime.now();
    await cloud.updateMyProgress(
      lastLoggedAt: _doseLogs.isEmpty ? null : _doseLogs.first.timestamp,
      weekStart: weekStartOf(now),
      doses: loggedThisWeek(_doseLogs, now),
      planned: plannedPerWeek(_compounds),
    );
  }

  // Sync ------------------------------------------------------------------------

  void _changed() {
    storage.setPendingSync(true);
    notifyListeners();
    _syncDebounce?.cancel();
    _syncDebounce = Timer(const Duration(milliseconds: 1500), sync);
  }

  /// Pushes local data to the cloud copy and refreshes the circle.
  /// Returns false when offline; the changes stay queued for the next try.
  Future<bool> sync() async {
    if (_isSyncing) {
      _syncAgain = true;
      return false;
    }
    _isSyncing = true;
    notifyListeners();
    try {
      final deletes = storage.pendingDeletes;
      await cloud.push(
        profile: _profile,
        compounds: _compounds,
        doseLogs: _doseLogs,
        checkIns: _checkIns,
        deletes: deletes,
      );
      await storage.removePendingDeletes(deletes);
      await storage.setPendingSync(false);
      await storage.setLastSyncTimestamp(DateTime.now());
      _syncError = null;
      await _pushMyProgress();
      _circle = await cloud.fetchCircle();
      await storage.saveCircle(_circle);
      return true;
    } catch (e) {
      debugPrint('Sync failed: $e');
      _syncError = e is CloudException ? e.message : "Couldn't reach Omnya. Your data is safe on this phone.";
      await storage.setPendingSync(true);
      return false;
    } finally {
      _isSyncing = false;
      notifyListeners();
      if (_syncAgain) {
        _syncAgain = false;
        unawaited(sync());
      }
    }
  }

  /// Deletes her data everywhere: the cloud copy first, then this phone.
  Future<void> deleteAllData() async {
    await cloud.deleteEverything();
    _syncDebounce?.cancel();
    await storage.clearAll();
    _compounds = [];
    _doseLogs = [];
    _checkIns = [];
    _photos = [];
    _profile = null;
    _circle = null;
    _syncError = null;
    notifyListeners();
  }

  bool _disposed = false;

  // A sync can still be in flight when the app tears the repository down.
  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _syncDebounce?.cancel();
    super.dispose();
  }
}
