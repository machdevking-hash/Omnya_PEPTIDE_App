/// Onboarding answers. Nothing here is prefilled: every field is her own answer.
class UserProfile {
  final List<String> goals;
  final List<String> selectedCompounds;
  final String? experienceLevel;

  /// 'yes', 'irregular', 'birth_control' or 'no'.
  final String? cycleStatus;

  /// Her 90-day goal in her own words, shown back at day 30 and day 90.
  final String day90GoalText;
  final String? photoTrackingType; // 'face', 'body' or 'both'
  final bool sundayPhotoPromptEnabled;

  /// Local reminders on dose days, at [reminderMinutes] after midnight.
  final bool remindersOn;
  final int reminderMinutes;

  /// Grams a day she aims for. Null until she sets one.
  final int? proteinTargetG;

  /// Asks for Face ID before the app opens.
  final bool lockWithFaceId;
  final DateTime createdAt;

  const UserProfile({
    this.goals = const [],
    this.selectedCompounds = const [],
    this.experienceLevel,
    this.cycleStatus,
    this.day90GoalText = '',
    this.photoTrackingType,
    this.sundayPhotoPromptEnabled = true,
    this.remindersOn = true,
    this.reminderMinutes = 9 * 60,
    this.lockWithFaceId = false,
    this.proteinTargetG,
    required this.createdAt,
  });

  /// Cycle features stay on unless she said she doesn't get a period.
  bool get hasCycle => cycleStatus != null && cycleStatus != 'no';

  Map<String, dynamic> toJson() => {
    'goals': goals,
    'selectedCompounds': selectedCompounds,
    'experienceLevel': experienceLevel,
    'cycleStatus': cycleStatus,
    'day90GoalText': day90GoalText,
    'photoTrackingType': photoTrackingType,
    'sundayPhotoPromptEnabled': sundayPhotoPromptEnabled,
    'remindersOn': remindersOn,
    'reminderMinutes': reminderMinutes,
    'lockWithFaceId': lockWithFaceId,
    'proteinTargetG': proteinTargetG,
    'createdAt': createdAt.toIso8601String(),
  };

  /// Also reads older builds, which stored a `hasCycle` flag instead of the answer.
  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
    goals: List<String>.from(json['goals'] as List? ?? const []),
    selectedCompounds: List<String>.from(json['selectedCompounds'] as List? ?? const []),
    experienceLevel: json['experienceLevel'] as String?,
    cycleStatus:
        json['cycleStatus'] as String? ??
        switch (json['hasCycle']) {
          true => 'yes',
          false => 'no',
          _ => null,
        },
    day90GoalText: json['day90GoalText'] as String? ?? '',
    photoTrackingType: json['photoTrackingType'] as String?,
    sundayPhotoPromptEnabled: json['sundayPhotoPromptEnabled'] as bool? ?? true,
    remindersOn: json['remindersOn'] as bool? ?? true,
    reminderMinutes: json['reminderMinutes'] as int? ?? 9 * 60,
    lockWithFaceId: json['lockWithFaceId'] as bool? ?? false,
    proteinTargetG: json['proteinTargetG'] as int?,
    createdAt: DateTime.parse(json['createdAt'] as String),
  );

  UserProfile copyWith({
    bool? sundayPhotoPromptEnabled,
    bool? remindersOn,
    int? reminderMinutes,
    bool? lockWithFaceId,
    int? Function()? proteinTargetG,
  }) => UserProfile(
    goals: goals,
    selectedCompounds: selectedCompounds,
    experienceLevel: experienceLevel,
    cycleStatus: cycleStatus,
    day90GoalText: day90GoalText,
    photoTrackingType: photoTrackingType,
    sundayPhotoPromptEnabled: sundayPhotoPromptEnabled ?? this.sundayPhotoPromptEnabled,
    remindersOn: remindersOn ?? this.remindersOn,
    reminderMinutes: reminderMinutes ?? this.reminderMinutes,
    lockWithFaceId: lockWithFaceId ?? this.lockWithFaceId,
    proteinTargetG: proteinTargetG != null ? proteinTargetG() : this.proteinTargetG,
    createdAt: createdAt,
  );
}
