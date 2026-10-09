import '../../core/constants/compound_directory.dart';
import 'dose_log.dart';

/// Rotation order for injection sites. A dose moves the compound's next site one step on.
const injectionSites = ['Left thigh', 'Right thigh', 'Left abdomen', 'Right abdomen', 'Left arm', 'Right arm'];

String siteAfter(String site) {
  final i = injectionSites.indexOf(site);
  return injectionSites[(i + 1) % injectionSites.length];
}

/// A site used within this many days shows as resting on the body map.
const siteRestDays = 7;

Map<String, DateTime> siteLastUsed(List<DoseLog> logs) {
  final out = <String, DateTime>{};
  for (final l in logs) {
    if (l.injectionSite.isEmpty) continue;
    final seen = out[l.injectionSite];
    if (seen == null || l.timestamp.isAfter(seen)) out[l.injectionSite] = l.timestamp;
  }
  return out;
}

const doseUnits = ['mg', 'mcg', 'IU'];
const routes = ['Subcutaneous', 'Intramuscular', 'Oral', 'Nasal', 'Topical'];

/// From [from] on, her dose is [dose]. She enters every step; the app never proposes one.
class TitrationStep {
  final DateTime from;
  final double dose;
  const TitrationStep(this.from, this.dose);

  Map<String, dynamic> toJson() => {'from': from.toIso8601String(), 'dose': dose};

  factory TitrationStep.fromJson(Map<String, dynamic> json) =>
      TitrationStep(DateTime.parse(json['from'] as String), (json['dose'] as num).toDouble());
}

class Compound {
  final String id;
  final String name;
  final String nickname;
  final CompoundCategory category;

  /// In [unit]. 0 until she enters it. The app never suggests a dose.
  final double dose;
  final String unit;
  final String route;
  final double? halfLifeHours;

  /// Later doses she has planned, oldest first. Empty means [dose] every time.
  final List<TitrationStep> titration;

  /// Days between doses. 0 until she sets a schedule.
  final int frequencyDays;
  final String nextSite;

  /// Null when she isn't tracking vial inventory or cost.
  final int? dosesLeft;
  final double? costPerDose;
  final double? vialMg;
  final double? bacWaterMl;

  /// When she mixed the current vial and how many days she keeps a mixed vial.
  final DateTime? mixedOn;
  final int? vialDays;
  final DateTime startDate;

  const Compound({
    required this.id,
    required this.name,
    required this.nickname,
    required this.category,
    this.dose = 0,
    this.unit = 'mg',
    this.route = 'Subcutaneous',
    this.halfLifeHours,
    this.titration = const [],
    this.frequencyDays = 0,
    this.nextSite = 'Left thigh',
    this.dosesLeft,
    this.costPerDose,
    this.vialMg,
    this.bacWaterMl,
    this.mixedOn,
    this.vialDays,
    required this.startDate,
  });

  bool get isConfigured => dose > 0 && frequencyDays > 0;

  bool get isInjected => route == 'Subcutaneous' || route == 'Intramuscular';

  /// The dose she planned for [day]: the latest titration step that has started, else [dose].
  double doseOn(DateTime day) {
    var d = dose;
    for (final s in titration) {
      if (!s.from.isAfter(day)) d = s.dose;
    }
    return d;
  }

  /// The day the mixed vial should be thrown out, when she tracks it.
  DateTime? get vialExpires =>
      mixedOn == null || vialDays == null ? null : DateTime(mixedOn!.year, mixedOn!.month, mixedOn!.day + vialDays!);

  double? get monthlyCost => costPerDose == null || frequencyDays == 0 ? null : costPerDose! * 30 / frequencyDays;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'nickname': nickname,
    'category': category.name,
    'doseMg': dose,
    'unit': unit,
    'route': route,
    'halfLifeHours': halfLifeHours,
    'titration': [for (final s in titration) s.toJson()],
    'frequencyDays': frequencyDays,
    'nextSite': nextSite,
    'dosesLeft': dosesLeft,
    'costPerDose': costPerDose,
    'vialMg': vialMg,
    'bacWaterMl': bacWaterMl,
    'mixedOn': mixedOn?.toIso8601String(),
    'vialDays': vialDays,
    'startDate': startDate.toIso8601String(),
  };

  /// Also reads builds before September 2026, which stored `injectionSite`.
  factory Compound.fromJson(Map<String, dynamic> json) => Compound(
    id: json['id'] as String,
    name: json['name'] as String,
    nickname: json['nickname'] as String? ?? '',
    category: CompoundCategory.values.firstWhere(
      (e) => e.name == json['category'],
      orElse: () => CompoundCategory.body,
    ),
    dose: (json['doseMg'] as num?)?.toDouble() ?? 0,
    unit: json['unit'] as String? ?? 'mg',
    route: json['route'] as String? ?? 'Subcutaneous',
    halfLifeHours: (json['halfLifeHours'] as num?)?.toDouble(),
    titration: [
      for (final s in json['titration'] as List? ?? const []) TitrationStep.fromJson(s as Map<String, dynamic>),
    ],
    frequencyDays: json['frequencyDays'] as int? ?? 0,
    nextSite: json['nextSite'] as String? ?? json['injectionSite'] as String? ?? injectionSites.first,
    dosesLeft: json['dosesLeft'] as int?,
    costPerDose: (json['costPerDose'] as num?)?.toDouble(),
    vialMg: (json['vialMg'] as num?)?.toDouble(),
    bacWaterMl: (json['bacWaterMl'] as num?)?.toDouble(),
    mixedOn: json['mixedOn'] == null ? null : DateTime.parse(json['mixedOn'] as String),
    vialDays: json['vialDays'] as int?,
    startDate: DateTime.parse(json['startDate'] as String),
  );

  Compound copyWith({
    String? name,
    String? nickname,
    CompoundCategory? category,
    double? dose,
    String? unit,
    String? route,
    double? Function()? halfLifeHours,
    List<TitrationStep>? titration,
    int? frequencyDays,
    String? nextSite,
    int? Function()? dosesLeft,
    double? Function()? costPerDose,
    double? Function()? vialMg,
    double? Function()? bacWaterMl,
    DateTime? Function()? mixedOn,
    int? Function()? vialDays,
    DateTime? startDate,
  }) {
    return Compound(
      id: id,
      name: name ?? this.name,
      nickname: nickname ?? this.nickname,
      category: category ?? this.category,
      dose: dose ?? this.dose,
      unit: unit ?? this.unit,
      route: route ?? this.route,
      halfLifeHours: halfLifeHours != null ? halfLifeHours() : this.halfLifeHours,
      titration: titration ?? this.titration,
      frequencyDays: frequencyDays ?? this.frequencyDays,
      nextSite: nextSite ?? this.nextSite,
      dosesLeft: dosesLeft != null ? dosesLeft() : this.dosesLeft,
      costPerDose: costPerDose != null ? costPerDose() : this.costPerDose,
      vialMg: vialMg != null ? vialMg() : this.vialMg,
      bacWaterMl: bacWaterMl != null ? bacWaterMl() : this.bacWaterMl,
      mixedOn: mixedOn != null ? mixedOn() : this.mixedOn,
      vialDays: vialDays != null ? vialDays() : this.vialDays,
      startDate: startDate ?? this.startDate,
    );
  }
}
