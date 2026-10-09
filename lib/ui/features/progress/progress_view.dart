import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/omnya_colors.dart';
import '../../../core/theme/omnya_typography.dart';
import '../../../core/widgets/omnya_card.dart';
import '../../../core/widgets/omnya_controls.dart';
import '../../../core/widgets/slide_page_route.dart';
import '../../../core/widgets/tactile_button.dart';
import '../../../data/models/daily_check_in.dart';
import '../../../data/models/progress_photo.dart';
import '../../../data/repositories/protocol_repository.dart';
import '../../../domain/insights.dart';
import '../../../domain/outcomes.dart';
import '../../../domain/schedule.dart';
import '../../core/omnya_header.dart';
import '../../onboarding/paywall_view.dart';
import '../photo_read/weekly_photo_view.dart';
import 'progress_card_sheet.dart';
import 'weekly_report_view.dart';

/// Spec page 2: photo slider, weight against cycle, one plain-English result.
class ProgressView extends StatelessWidget {
  const ProgressView({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<ProtocolRepository>();
    final highlight = progressHighlight(repo.checkIns, DateTime.now());

    return ListView(
      padding: const EdgeInsets.only(bottom: 120),
      children: [
        OmnyaHeader(
          title: 'Progress',
          subtitle: 'Your results, from your logs',
          trailing: OmnyaIconButton(
            icon: HugeIcons.strokeRoundedShare01,
            tooltip: 'Share a progress card',
            onPressed: () => showProgressCard(context),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _PhotoCompare(repo: repo),
              _MonthlyPhotos(repo: repo),
              const SizedBox(height: 16),
              _WeightCard(checkIns: repo.checkIns, hasCycle: repo.profile?.hasCycle ?? false),
              const SizedBox(height: 16),
              OmnyaCard(
                padding: const EdgeInsets.all(18),
                child: highlight == null
                    ? BlurredPreview(
                        message: 'Your first result shows up after two weeks of check-ins.',
                        child: _highlight('-4.2 lb', 'since you started, a steady drop.'),
                      )
                    : _highlight(highlight.stat, highlight.caption),
              ),
              const SizedBox(height: 16),
              _OutcomeCard(repo: repo),
              const SizedBox(height: 16),
              _TonedCard(repo: repo),
              const SizedBox(height: 16),
              OmnyaCard(
                padding: EdgeInsets.zero,
                child: InkWell(
                  borderRadius: BorderRadius.circular(OmnyaRadius.card),
                  onTap: () {
                    HapticFeedback.lightImpact();
                    Navigator.push(context, SlidePageRoute(page: const WeeklyReportView()));
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Row(
                      children: [
                        const HugeIcon(icon: HugeIcons.strokeRoundedCalendar03, color: OmnyaColors.plum, size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text('Your week', style: OmnyaTypography.label(weight: FontWeight.w600)),
                        ),
                        const HugeIcon(
                          icon: HugeIcons.strokeRoundedArrowRight01,
                          color: OmnyaColors.taupeDark,
                          size: 18,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

Widget _highlight(String stat, String caption) => Row(
  children: [
    Text(stat, style: OmnyaTypography.statNumber(color: OmnyaColors.plum)),
    const SizedBox(width: 14),
    Expanded(child: Text(caption, style: OmnyaTypography.bodyLarge())),
  ],
);

/// The outcome engine: from day 14, what changed since each compound started.
class _OutcomeCard extends StatelessWidget {
  final ProtocolRepository repo;
  const _OutcomeCard({required this.repo});

  @override
  Widget build(BuildContext context) {
    final report = outcomeReport(
      compounds: repo.compounds,
      logs: repo.doseLogs,
      checkIns: repo.checkIns,
      now: DateTime.now(),
    );
    final Widget body;
    if (report == null || !report.isReady) {
      body = BlurredPreview(
        message: report == null
            ? 'Log your first dose. Your results start reading back on day $outcomeStartDay.'
            : 'Day ${report.day}. Your first result is ready in ${report.daysToGo} ${report.daysToGo == 1 ? 'day' : 'days'}.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Energy up 1.2 points since you started.',
              style: OmnyaTypography.bodyLarge(color: OmnyaColors.charcoal),
            ),
            const SizedBox(height: 4),
            Text('12 of 12 doses on time.', style: OmnyaTypography.bodyMedium()),
            const SizedBox(height: 14),
            Text('Appetite down a little.', style: OmnyaTypography.bodyLarge(color: OmnyaColors.charcoal)),
          ],
        ),
      );
    } else if (report.compounds.isEmpty && report.sideEffects.isEmpty) {
      body = Text(
        'Keep checking in. Results show once a compound has two weeks of logs.',
        style: OmnyaTypography.bodyMedium(),
      );
    } else {
      body = ProGate(
        message: 'Your results are in. See them with Pro.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final o in report.compounds) ...[
              Text(o.headline, style: OmnyaTypography.bodyLarge(color: OmnyaColors.charcoal)),
              if (o.dosesLine.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(o.dosesLine, style: OmnyaTypography.bodyMedium()),
              ],
              const SizedBox(height: 14),
            ],
            for (final e in report.sideEffects)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(e, style: OmnyaTypography.bodyMedium()),
              ),
          ],
        ),
      );
    }
    return OmnyaCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('What changed', style: OmnyaTypography.label(weight: FontWeight.w600)),
          const SizedBox(height: 10),
          body,
        ],
      ),
    );
  }
}

/// Spec page 6, muscle: a protein target she sets and a weekly strength check-in, read as one score.
class _TonedCard extends StatelessWidget {
  final ProtocolRepository repo;
  const _TonedCard({required this.repo});

  @override
  Widget build(BuildContext context) {
    final profile = repo.profile;
    final score = tonedScore(repo.checkIns, profile?.proteinTargetG, DateTime.now());
    return OmnyaCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Toned, not frail', style: OmnyaTypography.label(weight: FontWeight.w600)),
          const SizedBox(height: 10),
          if (score == null)
            Text(
              'Set a protein target, then add protein and strength in your check-in. Your score shows here.',
              style: OmnyaTypography.bodyMedium(),
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${score.score}', style: OmnyaTypography.statNumber(color: OmnyaColors.plum)),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [for (final l in score.lines) Text(l, style: OmnyaTypography.bodyMedium())],
                  ),
                ),
              ],
            ),
          if (profile != null) ...[
            const SizedBox(height: 14),
            OmnyaWheelField(
              label: 'Daily protein target',
              value: profile.proteinTargetG?.toDouble(),
              min: 40,
              max: 250,
              step: 5,
              start: 100,
              unit: 'g',
              onChanged: (v) => repo.updateSettings(profile.copyWith(proteinTargetG: () => v?.round())),
            ),
          ],
        ],
      ),
    );
  }
}

/// Spec page 3: the monthly side-by-side. The first photo of each month, oldest first.
class _MonthlyPhotos extends StatelessWidget {
  final ProtocolRepository repo;
  const _MonthlyPhotos({required this.repo});

  @override
  Widget build(BuildContext context) {
    final byMonth = <String, ProgressPhoto>{};
    for (final p in repo.photos) {
      byMonth.putIfAbsent(DateFormat('MMM y').format(p.takenAt), () => p);
    }
    if (byMonth.length < 2) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Month by month', style: OmnyaTypography.label(weight: FontWeight.w600)),
          const SizedBox(height: 8),
          SizedBox(
            height: 150,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: byMonth.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final p = byMonth.values.elementAt(i);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(OmnyaRadius.control),
                      child: Image.file(
                        repo.photoFile(p),
                        width: 96,
                        height: 128,
                        fit: BoxFit.cover,
                        cacheWidth: 288,
                        errorBuilder: (_, _, _) => Container(width: 96, height: 128, color: OmnyaColors.sandMuted),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(DateFormat('MMM').format(p.takenAt), style: OmnyaTypography.tag(color: OmnyaColors.taupeDark)),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _PhotoCompare extends StatefulWidget {
  final ProtocolRepository repo;
  const _PhotoCompare({required this.repo});

  @override
  State<_PhotoCompare> createState() => _PhotoCompareState();
}

class _PhotoCompareState extends State<_PhotoCompare> {
  double _split = 0.5;

  void _openPhotos() {
    HapticFeedback.lightImpact();
    Navigator.push(context, SlidePageRoute(page: const WeeklyPhotoView()));
  }

  @override
  Widget build(BuildContext context) {
    final photos = widget.repo.photos;
    if (photos.isEmpty) {
      return OmnyaCard(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
        child: OmnyaEmptyState(
          icon: const HugeIcon(icon: HugeIcons.strokeRoundedCameraSmile02, color: OmnyaColors.taupeDark, size: 28),
          title: 'Before and after starts here',
          body: 'Take one photo a week. Your first and latest sit side by side.',
          action: TactileButton(label: "Take this week's photo", onPressed: _openPhotos),
        ),
      );
    }

    final first = photos.first;
    final latest = photos.last;
    final fmt = DateFormat('MMM d');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(fmt.format(first.takenAt), style: OmnyaTypography.tag(color: OmnyaColors.taupeDark)),
            if (photos.length > 1)
              Text(fmt.format(latest.takenAt), style: OmnyaTypography.tag(color: OmnyaColors.taupeDark)),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(OmnyaRadius.card),
          child: AspectRatio(
            aspectRatio: 1,
            child: photos.length == 1
                ? _photo(first)
                : LayoutBuilder(
                    builder: (context, box) => GestureDetector(
                      onHorizontalDragUpdate: (d) =>
                          setState(() => _split = (d.localPosition.dx / box.maxWidth).clamp(0.05, 0.95)),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          _photo(latest),
                          ClipRect(clipper: _LeftOf(_split), child: _photo(first)),
                          Positioned(
                            left: box.maxWidth * _split - 1,
                            top: 0,
                            bottom: 0,
                            child: Container(width: 2, color: OmnyaColors.cream),
                          ),
                          Positioned(
                            left: box.maxWidth * _split - 18,
                            top: box.maxHeight / 2 - 18,
                            child: Container(
                              width: 36,
                              height: 36,
                              decoration: const BoxDecoration(color: OmnyaColors.cream, shape: BoxShape.circle),
                              child: const Center(
                                child: HugeIcon(
                                  icon: HugeIcons.strokeRoundedChevronsLeftRight,
                                  color: OmnyaColors.charcoal,
                                  size: 18,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
        ),
        if (photos.length == 1) ...[
          const SizedBox(height: 8),
          Text("Next week's photo turns this into a before and after.", style: OmnyaTypography.bodySmall()),
        ],
      ],
    );
  }

  Widget _photo(ProgressPhoto p) => Image.file(
    widget.repo.photoFile(p),
    fit: BoxFit.cover,
    gaplessPlayback: true,
    errorBuilder: (_, _, _) => Container(
      color: OmnyaColors.sandMuted,
      alignment: Alignment.center,
      child: const HugeIcon(icon: HugeIcons.strokeRoundedImageNotFound01, color: OmnyaColors.taupeDark, size: 28),
    ),
  );
}

class _LeftOf extends CustomClipper<Rect> {
  final double fraction;
  _LeftOf(this.fraction);

  @override
  Rect getClip(Size size) => Rect.fromLTRB(0, 0, size.width * fraction, size.height);

  @override
  bool shouldReclip(_LeftOf old) => old.fraction != fraction;
}

class _WeightCard extends StatelessWidget {
  final List<DailyCheckIn> checkIns;
  final bool hasCycle;
  const _WeightCard({required this.checkIns, required this.hasCycle});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final since = addDays(dayOf(now), -90);
    final weighed = checkIns.where((c) => c.weightLbs != null && !c.date.isBefore(since)).toList()
      ..sort((a, b) => a.date.compareTo(b.date));

    return OmnyaCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Weight', style: OmnyaTypography.label(weight: FontWeight.w600)),
          if (hasCycle && weighed.length >= 2) ...[
            const SizedBox(height: 4),
            Text('Shaded days are the week before a period you logged.', style: OmnyaTypography.bodySmall()),
          ],
          const SizedBox(height: 16),
          if (weighed.length < 2)
            SizedBox(
              height: 150,
              child: BlurredPreview(
                message: weighed.isEmpty
                    ? 'Add your weight in the daily check-in to see your trend here.'
                    : 'One more weigh-in and your trend line appears.',
                child: _chart(_sample(now)),
              ),
            )
          else
            SizedBox(height: 150, child: _chart(weighed)),
        ],
      ),
    );
  }

  static List<DailyCheckIn> _sample(DateTime now) => [
    for (final (i, lb) in const [158.4, 157.9, 158.1, 157.2, 156.8, 156.9, 156.1, 155.6].indexed)
      DailyCheckIn(id: 'sample$i', date: addDays(dayOf(now), (i - 7) * 4), weightLbs: lb),
  ];

  Widget _chart(List<DailyCheckIn> weighed) {
    final start = dayOf(weighed.first.date);
    double x(DateTime d) => daysBetween(start, d).toDouble();
    final spots = [for (final c in weighed) FlSpot(x(c.date), c.weightLbs!)];
    final ys = spots.map((s) => s.y);
    final minY = ys.reduce((a, b) => a < b ? a : b) - 2;
    final maxY = ys.reduce((a, b) => a > b ? a : b) + 2;
    final maxX = spots.last.x == 0 ? 1.0 : spots.last.x;

    final bands = <VerticalRangeAnnotation>[
      if (hasCycle)
        for (final p in checkIns.where((c) => c.periodStarted))
          if (x(p.date) > 0 && x(p.date) - 7 < maxX)
            VerticalRangeAnnotation(
              x1: (x(p.date) - 7).clamp(0, maxX).toDouble(),
              x2: x(p.date).clamp(0, maxX).toDouble(),
              color: OmnyaColors.plumSoft.withValues(alpha: 0.12),
            ),
    ];

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: maxX,
        minY: minY,
        maxY: maxY,
        gridData: const FlGridData(show: false),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        rangeAnnotations: RangeAnnotations(verticalRangeAnnotations: bands),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => OmnyaColors.charcoal,
            tooltipBorderRadius: BorderRadius.circular(OmnyaRadius.chip),
            getTooltipItems: (touched) => [
              for (final t in touched)
                LineTooltipItem(
                  '${t.y.toStringAsFixed(1)} lb\n${DateFormat('MMM d').format(addDays(start, t.x.round()))}',
                  OmnyaTypography.label(color: OmnyaColors.cream, weight: FontWeight.w600),
                ),
            ],
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.3,
            preventCurveOverShooting: true,
            color: OmnyaColors.plum,
            barWidth: 2.5,
            isStrokeCapRound: true,
            dotData: FlDotData(show: spots.length <= 12),
          ),
        ],
      ),
    );
  }
}
