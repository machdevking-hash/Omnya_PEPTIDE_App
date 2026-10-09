import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/circle_data.dart';
import '../models/compound.dart';
import '../models/daily_check_in.dart';
import '../models/dose_log.dart';
import '../models/user_profile.dart';
import 'local_storage_service.dart';

/// A failure worth showing to her, already in plain words.
class CloudException implements Exception {
  final String message;
  const CloudException(this.message);

  @override
  String toString() => message;
}

/// Backup and circles, straight to Supabase. Row level security (supabase/schema.sql)
/// is what keeps each person's rows private; there is no server in between.
class CloudService {
  static const _url = String.fromEnvironment('SUPABASE_URL', defaultValue: 'https://aeddscoqzqwnjwokflnz.supabase.co');

  // A publishable key is meant to ship inside apps. It grants nothing on its own.
  static const _publishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: 'sb_publishable_Ngbc6wpe22CGbsGD9-bXBw_rJS0rSUm',
  );

  static Future<void> initialize() => Supabase.initialize(url: _url, publishableKey: _publishableKey);

  SupabaseClient get _db => Supabase.instance.client;

  String? get currentUserId => _db.auth.currentUser?.id;

  /// Her user id. An install signs in anonymously the first time it needs the cloud,
  /// so a slow network never holds up app start.
  Future<String> userId() async {
    final current = _db.auth.currentUser;
    if (current != null) return current.id;
    final res = await _db.auth.signInAnonymously().timeout(const Duration(seconds: 15));
    final user = res.user;
    if (user == null) throw const CloudException('Sign-in returned no user.');
    return user.id;
  }

  /// Mirrors this device's data to the cloud copy. Every row is sent each time.
  // ponytail: full upload per sync; switch to per-row dirty flags if a log grows past a few thousand rows.
  Future<void> push({
    required UserProfile? profile,
    required List<Compound> compounds,
    required List<DoseLog> doseLogs,
    required List<DailyCheckIn> checkIns,
    required List<PendingDelete> deletes,
  }) async {
    final uid = await userId();
    final now = DateTime.now().toUtc().toIso8601String();

    for (final table in {for (final d in deletes) d.table}) {
      final ids = [
        for (final d in deletes)
          if (d.table == table) d.id,
      ];
      await _db.from(table).delete().eq('user_id', uid).inFilter('id', ids);
    }

    if (profile != null) {
      await _db.from('profiles').upsert({
        'id': uid,
        'goals': profile.goals,
        'selected_compounds': profile.selectedCompounds,
        'experience_level': profile.experienceLevel,
        'cycle_status': profile.cycleStatus,
        'day_90_goal': profile.day90GoalText,
        'photo_tracking_type': profile.photoTrackingType,
        'sunday_photo_prompt': profile.sundayPhotoPromptEnabled,
        'protein_target_g': profile.proteinTargetG,
        'updated_at': now,
      });
    }

    if (compounds.isNotEmpty) {
      await _db.from('compounds').upsert([
        for (final c in compounds)
          {
            'user_id': uid,
            'id': c.id,
            'name': c.name,
            'nickname': c.nickname,
            'category': c.category.name,
            'dose': c.dose,
            'unit': c.unit,
            'route': c.route,
            'half_life_hours': c.halfLifeHours,
            'titration': [for (final t in c.titration) t.toJson()],
            'mixed_on': c.mixedOn == null ? null : _day(c.mixedOn!),
            'vial_days': c.vialDays,
            'frequency_days': c.frequencyDays,
            'next_site': c.nextSite,
            'doses_left': c.dosesLeft,
            'cost_per_dose': c.costPerDose,
            'vial_mg': c.vialMg,
            'bac_water_ml': c.bacWaterMl,
            'start_date': _day(c.startDate),
            'updated_at': now,
          },
      ], onConflict: 'user_id,id');
    }

    if (doseLogs.isNotEmpty) {
      await _db.from('dose_logs').upsert([
        for (final l in doseLogs)
          {
            'user_id': uid,
            'id': l.id,
            'compound_id': l.compoundId,
            'compound_name': l.compoundName,
            'dose': l.dose,
            'unit': l.unit,
            'injection_site': l.injectionSite.isEmpty ? null : l.injectionSite,
            'logged_at': l.timestamp.toUtc().toIso8601String(),
          },
      ], onConflict: 'user_id,id');
    }

    if (checkIns.isNotEmpty) {
      await _db.from('check_ins').upsert([
        for (final c in checkIns)
          {
            'user_id': uid,
            'id': c.id,
            'checked_at': c.date.toUtc().toIso8601String(),
            'energy': c.energyLevel,
            'appetite': c.appetiteLevel,
            'weight_lbs': c.weightLbs,
            'waist_in': c.waistIn,
            'sleep_hours': c.sleepHours,
            'pain': c.pain,
            'side_effects': c.sideEffects,
            'protein_g': c.proteinG,
            'strength': c.strength,
            'notes': c.notes,
            'period_started': c.periodStarted,
          },
      ], onConflict: 'user_id,id');
    }
  }

  static const _circleColumns =
      'id, name, owner_id, max_members, '
      'circle_members(user_id, display_name, last_logged_at, week_start, doses_this_week, '
      'doses_planned_this_week, joined_at)';

  Future<Circle?> fetchCircle() async {
    final uid = await userId();
    final mine = await _db.from('circle_members').select('circle_id').eq('user_id', uid).maybeSingle();
    if (mine == null) return null;
    final row = await _db
        .from('circles')
        .select(_circleColumns)
        .eq('id', mine['circle_id'] as String)
        .order('joined_at', referencedTable: 'circle_members')
        .single();
    return Circle.fromRow(row);
  }

  Future<Circle> createCircle(String displayName) {
    return _friendly(() async {
      final uid = await userId();
      for (var attempt = 0; attempt < 5; attempt++) {
        final code = generateInviteCode();
        try {
          await _db.from('circles').insert({'id': code, 'name': "$displayName's circle", 'owner_id': uid});
        } on PostgrestException catch (e) {
          if (e.code == '23505') continue; // code already taken, draw another
          rethrow;
        }
        await _db.from('circle_members').insert({'circle_id': code, 'user_id': uid, 'display_name': displayName});
        return (await fetchCircle())!;
      }
      throw const CloudException("Couldn't create a circle. Try again.");
    });
  }

  Future<Circle> joinCircle(String code, String displayName) {
    return _friendly(() async {
      final uid = await userId();
      // Asking for the row back would fail: she can only read the circle once she is in it.
      await _db.from('circle_members').insert({'circle_id': code, 'user_id': uid, 'display_name': displayName});
      return (await fetchCircle())!;
    });
  }

  Future<void> leaveCircle() {
    return _friendly(() async {
      final uid = await userId();
      await _db.from('circle_members').delete().eq('user_id', uid);
    });
  }

  Future<void> updateMyProgress({
    required DateTime? lastLoggedAt,
    required DateTime weekStart,
    required int doses,
    required int planned,
  }) async {
    final uid = await userId();
    await _db
        .from('circle_members')
        .update({
          'last_logged_at': lastLoggedAt?.toUtc().toIso8601String(),
          'week_start': _day(weekStart),
          'doses_this_week': doses,
          'doses_planned_this_week': planned,
        })
        .eq('user_id', uid);
  }

  /// Deletes her rows from the cloud copy and signs this install out.
  /// Circles she started stay for the people still in them.
  Future<void> deleteEverything() async {
    await _friendly(() async {
      final uid = await userId();
      for (final table in ['circle_members', 'dose_logs', 'check_ins', 'compounds']) {
        await _db.from(table).delete().eq('user_id', uid);
      }
      await _db.from('profiles').delete().eq('id', uid);
    });
    try {
      await _db.auth.signOut();
    } on Exception catch (e) {
      // The rows are already gone; the local session is cleared with the rest of the phone's data.
      debugPrint('Sign-out after delete failed: $e');
    }
  }

  /// Five characters without 0, O, 1 or I. Matches the check in schema.sql.
  static String generateInviteCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rnd = Random.secure();
    return List.generate(5, (_) => chars[rnd.nextInt(chars.length)]).join();
  }

  static Future<T> _friendly<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on PostgrestException catch (e) {
      throw CloudException(switch (e.code) {
        '23503' => 'No circle uses that code. Check it and try again.',
        '42501' => 'That circle is full. Circles hold 5 people.',
        '23505' => "You're already in a circle. Leave it first to join another.",
        _ => 'Something went wrong on our side. Try again in a moment.',
      });
    } on CloudException {
      rethrow;
    } on Exception catch (e) {
      debugPrint('Cloud request failed: $e');
      throw const CloudException("Couldn't reach Omnya. Check your connection and try again.");
    }
  }

  static String _day(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
