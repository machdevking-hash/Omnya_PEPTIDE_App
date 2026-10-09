import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/compound_directory.dart';
import '../../../core/theme/omnya_colors.dart';
import '../../../core/theme/omnya_typography.dart';
import '../../../core/widgets/omnya_controls.dart';
import '../../../core/widgets/tactile_button.dart';
import '../../../data/models/compound.dart';
import '../../../data/repositories/protocol_repository.dart';
import '../../../domain/schedule.dart';
import 'calculator_modal.dart';

/// Add a compound, or edit one when [compound] is given.
Future<void> showCompoundEditor(BuildContext context, {Compound? compound}) =>
    showOmnyaSheet(context, builder: (_) => _CompoundEditor(compound: compound));

class _CompoundEditor extends StatefulWidget {
  final Compound? compound;
  const _CompoundEditor({this.compound});

  @override
  State<_CompoundEditor> createState() => _CompoundEditorState();
}

class _CompoundEditorState extends State<_CompoundEditor> {
  late final Compound? _c = widget.compound;
  late final _name = TextEditingController(text: _c?.name ?? '');
  late final _nickname = TextEditingController(text: _c?.nickname ?? '');
  late final _dose = TextEditingController(text: _c == null || _c.dose == 0 ? '' : _trim(_c.dose));
  late final _halfLife = TextEditingController(text: _c?.halfLifeHours == null ? '' : _trim(_c!.halfLifeHours!));
  late int? _vialDays = _c?.vialDays;
  late String _unit = _c?.unit ?? 'mg';
  late String _route = _c?.route ?? 'Subcutaneous';
  late List<TitrationStep> _titration = [...?_c?.titration];
  late DateTime? _mixedOn = _c?.mixedOn;
  late int? _dosesLeft = _c?.dosesLeft;
  late final _cost = TextEditingController(text: _c?.costPerDose?.toStringAsFixed(2) ?? '');
  late CompoundCategory _category = _c?.category ?? CompoundCategory.body;
  late int _every = _c?.frequencyDays ?? 0;
  late String _site = _c?.nextSite ?? injectionSites.first;
  late DateTime _start = _c?.startDate ?? dayOf(DateTime.now());
  double? _vialMg;
  double? _bacWaterMl;
  final _errors = <String, String>{};

  @override
  void initState() {
    super.initState();
    _vialMg = _c?.vialMg;
    _bacWaterMl = _c?.bacWaterMl;
  }

  @override
  void dispose() {
    for (final c in [_name, _nickname, _dose, _cost, _halfLife]) {
      c.dispose();
    }
    super.dispose();
  }

  static String _trim(double v) => v.toString().replaceFirst(RegExp(r'\.0$'), '');

  void _pickPreset(CompoundPreset p) {
    HapticFeedback.selectionClick();
    setState(() {
      _name.text = p.name;
      _nickname.text = p.nickname;
      _category = p.category;
      _errors.remove('name');
    });
  }

  Future<void> _pickStart() async {
    final today = dayOf(DateTime.now());
    final picked = await pickDate(
      context,
      title: 'Started',
      initial: _start,
      first: DateTime(today.year - 3),
      last: today,
    );
    if (picked != null) setState(() => _start = picked);
  }

  Future<DateTime?> _pickDay(String title, DateTime initial, {required DateTime first, required DateTime last}) =>
      pickDate(context, title: title, initial: initial, first: first, last: last);

  Future<void> _pickMixed() async {
    final today = dayOf(DateTime.now());
    final picked = await _pickDay('Mixed on', _mixedOn ?? today, first: addDays(today, -365), last: today);
    if (picked != null) setState(() => _mixedOn = picked);
  }

  Future<void> _addStep() async {
    final today = dayOf(DateTime.now());
    final last = _titration.isEmpty ? today : _titration.last.from;
    final day = await _pickDay(
      'New dose starts',
      addDays(last, 7),
      first: addDays(today, -365),
      last: addDays(today, 730),
    );
    if (day == null || !mounted) return;
    final amount = TextEditingController();
    final dose = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Dose from ${DateFormat('MMM d').format(day)}', style: OmnyaTypography.headline()),
        content: OmnyaField.number(label: 'Your dose', controller: amount, suffix: _unit, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              final v = parseNumber(amount.text);
              if (v != null && v > 0 && v <= 10000) Navigator.pop(ctx, v);
            },
            child: Text(
              'Add',
              style: OmnyaTypography.label(color: OmnyaColors.plum, weight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    amount.dispose();
    if (dose == null) return;
    setState(() {
      _titration = [..._titration.where((s) => !sameDay(s.from, day)), TitrationStep(day, dose)]
        ..sort((a, b) => a.from.compareTo(b.from));
    });
  }

  // The calculator works in mg; mcg converts both ways.
  double get _toMg => _unit == 'mcg' ? 0.001 : 1;

  Future<void> _openCalculator() async {
    final typed = parseNumber(_dose.text);
    final result = await showCalculator(context, targetDoseMg: typed == null ? null : typed * _toMg, forCompound: true);
    if (result == null || !mounted) return;
    setState(() {
      _vialMg = result.vialMg;
      _bacWaterMl = result.bacWaterMl;
      _dose.text = _trim(double.parse((result.targetDoseMg / _toMg).toStringAsFixed(3)));
      _dosesLeft = result.totalDosesPerVial.clamp(0, 999);
      if (result.costPerDose > 0) _cost.text = result.costPerDose.toStringAsFixed(2);
    });
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final dose = parseNumber(_dose.text);
    final costText = _cost.text.trim().replaceAll(r'$', '');
    final cost = costText.isEmpty ? null : parseNumber(costText);
    final halfText = _halfLife.text.trim();
    final half = halfText.isEmpty ? null : parseNumber(halfText);

    setState(() {
      _errors.clear();
      if (name.isEmpty) _errors['name'] = 'Give it a name';
      if (dose == null || dose <= 0 || dose > 10000) _errors['dose'] = 'Enter your dose in $_unit';
      if (_every == 0) _errors['every'] = 'Choose how often you take it';
      if (halfText.isNotEmpty && (half == null || half <= 0 || half > 5000)) _errors['half'] = 'Enter hours, like 36';
      if (costText.isNotEmpty && (cost == null || cost < 0 || cost > 99999)) {
        _errors['cost'] = 'Enter an amount, like 4.10';
      }
    });
    if (_errors.isNotEmpty) {
      HapticFeedback.heavyImpact();
      return;
    }

    final repo = context.read<ProtocolRepository>();
    final base = _c ?? repo.newCompound(name, startDate: _start);
    await repo.saveCompound(
      base.copyWith(
        name: name,
        nickname: _nickname.text.trim(),
        category: _category,
        dose: dose,
        unit: _unit,
        route: _route,
        halfLifeHours: () => half,
        titration: _titration,
        mixedOn: () => _mixedOn,
        vialDays: () => _mixedOn == null ? null : _vialDays,
        frequencyDays: _every,
        nextSite: _site,
        startDate: _start,
        dosesLeft: () => _dosesLeft,
        costPerDose: () => cost,
        vialMg: () => _vialMg,
        bacWaterMl: () => _bacWaterMl,
      ),
    );
    HapticFeedback.mediumImpact();
    if (mounted) Navigator.pop(context);
  }

  Future<void> _remove() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove ${_c!.name}?', style: OmnyaTypography.headline()),
        content: Text(
          'It leaves your stack. Doses you already logged stay in your history.',
          style: OmnyaTypography.bodyMedium(),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Remove',
              style: OmnyaTypography.label(color: OmnyaColors.error, weight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final repo = context.read<ProtocolRepository>();
    await repo.deleteCompound(_c!.id);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(_c == null ? 'Add a compound' : 'Edit ${_c.name}', style: OmnyaTypography.headline()),
        const SizedBox(height: 6),
        Text('You enter the dose and schedule. Omnya only keeps track.', style: OmnyaTypography.bodySmall()),
        const SizedBox(height: 20),
        if (_c == null) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final p in CompoundDirectory.presets)
                _Chip(label: p.name, selected: _name.text == p.name, onTap: () => _pickPreset(p)),
            ],
          ),
          const SizedBox(height: 16),
        ],
        OmnyaField(
          label: 'Name',
          controller: _name,
          hint: 'Or type your own',
          error: _errors['name'],
          capitalization: TextCapitalization.words,
          maxLength: 40,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 14),
        OmnyaField(
          label: 'Nickname (optional)',
          controller: _nickname,
          hint: 'What you call it',
          maxLength: 40,
          capitalization: TextCapitalization.sentences,
        ),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: OmnyaField.number(label: 'Dose', controller: _dose, suffix: _unit, error: _errors['dose']),
            ),
            const SizedBox(width: 10),
            Padding(
              padding: EdgeInsets.only(bottom: _errors['dose'] == null ? 6 : 28),
              child: Wrap(
                spacing: 6,
                children: [
                  for (final u in doseUnits)
                    _Chip(label: u, selected: _unit == u, onTap: () => setState(() => _unit = u)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Text('How you take it', style: OmnyaTypography.label(color: OmnyaColors.charcoalMuted)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final r in routes) _Chip(label: r, selected: _route == r, onTap: () => setState(() => _route = r)),
          ],
        ),
        const SizedBox(height: 18),
        Text('How often', style: OmnyaTypography.label(color: OmnyaColors.charcoalMuted)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _Chip(label: 'Daily', selected: _every == 1, onTap: () => setState(() => _every = 1)),
            _Chip(label: 'Weekly', selected: _every == 7, onTap: () => setState(() => _every = 7)),
          ],
        ),
        const SizedBox(height: 10),
        OmnyaWheelField(
          label: 'Or pick a schedule',
          value: _every == 0 ? null : _every.toDouble(),
          min: 1,
          max: 90,
          start: 3,
          format: (v) => everyLabel(v.round()),
          onChanged: (v) => setState(() => _every = v?.round() ?? 0),
        ),
        if (_errors['every'] != null) ...[
          const SizedBox(height: 6),
          Text(_errors['every']!, style: OmnyaTypography.bodySmall(color: OmnyaColors.error)),
        ],
        if (_route == 'Subcutaneous' || _route == 'Intramuscular') ...[
          const SizedBox(height: 18),
          Text('Next site', style: OmnyaTypography.label(color: OmnyaColors.charcoalMuted)),
          const SizedBox(height: 4),
          Text(
            'Sites used in the last $siteRestDays days are resting. Logging moves to the next site in order.',
            style: OmnyaTypography.bodySmall(),
          ),
          const SizedBox(height: 10),
          _SiteMap(
            selected: _site,
            lastUsed: siteLastUsed(context.read<ProtocolRepository>().doseLogs),
            onSelect: (s) => setState(() => _site = s),
          ),
        ],
        const SizedBox(height: 18),
        InkWell(
          onTap: _pickStart,
          borderRadius: BorderRadius.circular(OmnyaRadius.control),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Text('Started', style: OmnyaTypography.label(color: OmnyaColors.charcoalMuted)),
                ),
                Text(
                  DateFormat('MMM d, y').format(_start),
                  style: OmnyaTypography.label(color: OmnyaColors.plum, weight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 28),
        Text('Dose changes (optional)', style: OmnyaTypography.label(weight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(
          'If your dose steps up on set dates, add each step. The day\'s dose follows it.',
          style: OmnyaTypography.bodySmall(),
        ),
        const SizedBox(height: 8),
        for (final step in _titration)
          Row(
            children: [
              Expanded(
                child: Text(
                  'From ${DateFormat('MMM d, y').format(step.from)} · ${formatDose(step.dose, _unit)}',
                  style: OmnyaTypography.bodyMedium(color: OmnyaColors.charcoal),
                ),
              ),
              IconButton(
                tooltip: 'Remove step',
                onPressed: () => setState(() => _titration = [..._titration]..remove(step)),
                icon: const Icon(Icons.close, size: 18, color: OmnyaColors.taupeDark),
              ),
            ],
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: _addStep,
            style: TextButton.styleFrom(padding: EdgeInsets.zero, foregroundColor: OmnyaColors.plum),
            child: Text(
              'Add a step',
              style: OmnyaTypography.label(color: OmnyaColors.plum, weight: FontWeight.w600),
            ),
          ),
        ),
        const SizedBox(height: 8),
        OmnyaField.number(
          label: 'Half-life (optional)',
          controller: _halfLife,
          suffix: 'hours',
          error: _errors['half'],
        ),
        const Divider(height: 28),
        Text('Vial (optional)', style: OmnyaTypography.label(weight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text('Add these to see when it runs out and what it costs.', style: OmnyaTypography.bodySmall()),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: OmnyaWheelField(
                label: 'Doses left',
                value: _dosesLeft?.toDouble(),
                min: 0,
                max: 999,
                start: 10,
                onChanged: (v) => setState(() => _dosesLeft = v?.round()),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OmnyaField.number(label: 'Cost per dose', controller: _cost, hint: r'$', error: _errors['cost']),
            ),
          ],
        ),
        const SizedBox(height: 6),
        InkWell(
          onTap: _pickMixed,
          borderRadius: BorderRadius.circular(OmnyaRadius.control),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Text('Mixed on', style: OmnyaTypography.label(color: OmnyaColors.charcoalMuted)),
                ),
                Text(
                  _mixedOn == null ? 'Add date' : DateFormat('MMM d, y').format(_mixedOn!),
                  style: OmnyaTypography.label(color: OmnyaColors.plum, weight: FontWeight.w600),
                ),
                if (_mixedOn != null)
                  GestureDetector(
                    onTap: () => setState(() => _mixedOn = null),
                    child: const Padding(
                      padding: EdgeInsets.only(left: 10),
                      child: Icon(Icons.close, size: 18, color: OmnyaColors.taupeDark),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (_mixedOn != null)
          OmnyaWheelField(
            label: 'Keep a mixed vial for',
            value: _vialDays?.toDouble(),
            min: 1,
            max: 365,
            start: 28,
            unit: 'days',
            onChanged: (v) => setState(() => _vialDays = v?.round()),
          ),
        if (_unit != 'IU')
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: _openCalculator,
              style: TextButton.styleFrom(padding: EdgeInsets.zero, foregroundColor: OmnyaColors.plum),
              child: Text(
                'Work these out with the calculator',
                style: OmnyaTypography.label(color: OmnyaColors.plum, weight: FontWeight.w600),
              ),
            ),
          ),
        const SizedBox(height: 12),
        TactileButton(label: _c == null ? 'Add to stack' : 'Save', width: double.infinity, onPressed: _save),
        if (_c != null) ...[
          const SizedBox(height: 8),
          TextButton(
            onPressed: _remove,
            child: Text(
              'Remove from stack',
              style: OmnyaTypography.label(color: OmnyaColors.error, weight: FontWeight.w600),
            ),
          ),
        ],
      ],
    );
  }
}

/// Spec page 6: a simple body map. Arms, abdomen and thighs, her left on the left,
/// each with how long it has rested.
class _SiteMap extends StatelessWidget {
  final String selected;
  final Map<String, DateTime> lastUsed;
  final ValueChanged<String> onSelect;
  const _SiteMap({required this.selected, required this.lastUsed, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    Widget cell(String site) {
      final used = lastUsed[site];
      final days = used == null ? null : daysBetween(used, now);
      final resting = days != null && days < siteRestDays;
      final isSelected = site == selected;
      final detail = switch (days) {
        null => 'Not used yet',
        0 => 'Used today',
        1 => 'Used yesterday',
        _ => '$days days ago',
      };
      return Expanded(
        child: Semantics(
          button: true,
          selected: isSelected,
          label: '$site, $detail${resting ? ', resting' : ''}',
          excludeSemantics: true,
          child: GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              onSelect(site);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: isSelected ? OmnyaColors.plum : (resting ? OmnyaColors.sandMuted : OmnyaColors.sand),
                borderRadius: BorderRadius.circular(OmnyaRadius.control),
                border: Border.all(color: isSelected ? OmnyaColors.plum : OmnyaColors.line),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    site,
                    style: OmnyaTypography.label(
                      color: isSelected ? OmnyaColors.cream : OmnyaColors.charcoal,
                      weight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    resting ? '$detail · resting' : detail,
                    style: isSelected
                        ? OmnyaTypography.bodySmall(color: OmnyaColors.sandMuted)
                        : OmnyaTypography.bodySmall(),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        for (final part in const ['arm', 'abdomen', 'thigh']) ...[
          Row(children: [cell('Left $part'), const SizedBox(width: 8), cell('Right $part')]),
          if (part != 'thigh') const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _Chip({required this.label, required this.selected, required this.onTap});

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
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? OmnyaColors.plum : OmnyaColors.sand,
            borderRadius: BorderRadius.circular(OmnyaRadius.chip),
            border: Border.all(color: selected ? OmnyaColors.plum : OmnyaColors.line),
          ),
          child: Text(label, style: OmnyaTypography.label(color: selected ? OmnyaColors.cream : OmnyaColors.charcoal)),
        ),
      ),
    );
  }
}
