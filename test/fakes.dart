import 'dart:io';
import 'package:omnya/data/models/circle_data.dart';
import 'package:omnya/data/models/compound.dart';
import 'package:omnya/data/models/daily_check_in.dart';
import 'package:omnya/data/models/dose_log.dart';
import 'package:omnya/data/models/user_profile.dart';
import 'package:omnya/data/repositories/protocol_repository.dart';
import 'package:omnya/data/services/cloud_service.dart';
import 'package:omnya/data/services/local_storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// In-memory stand-in for Supabase. Flip [offline] to simulate no network.
class FakeCloud implements CloudService {
  bool offline = false;
  int pushes = 0;
  List<PendingDelete> lastDeletes = const [];
  List<DoseLog> lastLogs = const [];
  Circle? circle;
  bool deleted = false;

  void _check() {
    if (offline) throw const SocketException('offline');
  }

  @override
  String? get currentUserId => 'me';

  @override
  Future<String> userId() async {
    _check();
    return 'me';
  }

  @override
  Future<void> push({
    required UserProfile? profile,
    required List<Compound> compounds,
    required List<DoseLog> doseLogs,
    required List<DailyCheckIn> checkIns,
    required List<PendingDelete> deletes,
  }) async {
    _check();
    pushes++;
    lastDeletes = deletes;
    lastLogs = doseLogs;
  }

  @override
  Future<Circle?> fetchCircle() async {
    _check();
    return circle;
  }

  @override
  Future<Circle> createCircle(String displayName) async {
    _check();
    return circle = Circle(
      code: 'K7M2Q',
      name: "$displayName's circle",
      ownerId: 'me',
      members: [CircleMember(userId: 'me', displayName: displayName)],
    );
  }

  @override
  Future<Circle> joinCircle(String code, String displayName) async {
    _check();
    if (code != 'P3RX9') throw const CloudException('No circle uses that code. Check it and try again.');
    return circle = Circle(
      code: code,
      name: "Ada's circle",
      ownerId: 'ada',
      members: [
        const CircleMember(userId: 'ada', displayName: 'Ada'),
        CircleMember(userId: 'me', displayName: displayName),
      ],
    );
  }

  @override
  Future<void> leaveCircle() async {
    _check();
    circle = null;
  }

  @override
  Future<void> updateMyProgress({
    required DateTime? lastLoggedAt,
    required DateTime weekStart,
    required int doses,
    required int planned,
  }) async => _check();

  @override
  Future<void> deleteEverything() async {
    if (offline) throw const CloudException("Couldn't reach Omnya. Check your connection and try again.");
    deleted = true;
  }
}

Future<ProtocolRepository> makeRepo(FakeCloud cloud, {Map<String, Object> prefs = const {}}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final storage = await LocalStorageService.init(photosDir: Directory.systemTemp.createTempSync('omnya_test'));
  return ProtocolRepository(storage: storage, cloud: cloud);
}

/// Lets the unawaited sync kicked off by the repository finish.
Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));
