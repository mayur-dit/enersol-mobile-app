import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../../core/data/customer_repository.dart';
import '../../core/models/customer_models.dart';
import '../../core/state/screen_refresh.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/app_shell.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/page_scaffold.dart';
import '../../core/utils/errors.dart';
import '../../core/utils/date_format.dart';

/// A system size as a customer would say it: "3 kW", not "3.0 kW".
///
/// `capacityKw` is a double all the way from Mongo, so interpolating it
/// straight put a pointless `.0` on every whole-number system — which is most
/// of them — right in the hero badge. One decimal is kept when there actually
/// is one, because 3.5 kW is a real size and rounding it to 4 would be a lie.
String fmtKw(num kw) {
  final rounded = (kw * 10).round() / 10;
  final text = rounded == rounded.roundToDouble()
      ? rounded.toStringAsFixed(0)
      : rounded.toStringAsFixed(1);
  return '$text kW';
}

/// Live output, the week's history, and what it all adds up to.
class GenerationScreen extends StatefulWidget {
  const GenerationScreen({super.key});

  @override
  State<GenerationScreen> createState() => _GenerationScreenState();
}

class _GenerationScreenState extends State<GenerationScreen>
    with ScreenRefresh {
  late Future<GenerationSummary?> _future;

  /// Readings are entered by the office, so this screen goes out of date
  /// exactly like the rest — quietly, while it sits behind the shell.
  @override
  int? get refreshTab => ShellTab.power;

  @override
  void initState() {
    super.initState();
    _future = context.read<CustomerRepository>().generation();
  }

  @override
  Future<void> loadData() async {
    setState(() {
      _future = context.read<CustomerRepository>().generation();
    });
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: refreshNow,
      color: AppColors.ember,
      child: FutureBuilder<GenerationSummary?>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.ember),
            );
          }

          // "Not commissioned" and "could not reach the server" are different
          // answers, and the empty state below only speaks the first one. A
          // customer whose system IS commissioned was being told it is not.
          if (snap.hasError) {
            return ErrorRetry(message: friendlyError(snap.error), onRetry: refreshNow);
          }

          final g = snap.data;
          if (g == null) {
            return const EmptyState(
              icon: Icons.bolt_outlined,
              title: 'Coming soon',
              subtitle:
                  'Live monitoring of your system is on the way. Your daily '
                  'generation will appear here once it is connected.',
            );
          }

          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: tabInsets(context),
            children: [
              const _ComingSoonNote(),
              const SizedBox(height: AppSpacing.md),
              _LiveHero(summary: g),
              const SizedBox(height: AppSpacing.lg),
              _StatGrid(summary: g),
              const SizedBox(height: AppSpacing.xl),
              const SectionTitle('Last 7 days'),
              _WeekCard(points: g.last7Days),
              const SizedBox(height: AppSpacing.xl),
              const SectionTitle('Your impact'),
              _ImpactCard(summary: g),
            ],
          );
        },
      ),
    );
  }
}

/// Says plainly that this screen is not finished yet.
///
/// Shown above real figures, not instead of them: the readings below are
/// genuine — an engineer types them in from the meter — but they are not the
/// live, self-updating monitoring this screen is built for, and a customer
/// comparing a once-a-day figure against their inverter deserves to know which
/// of the two they are looking at.
class _ComingSoonNote extends StatelessWidget {
  const _ComingSoonNote();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm + 2,
      ),
      decoration: BoxDecoration(
        color: AppColors.info.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.info.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.schedule_rounded, size: 17, color: AppColors.info),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Live monitoring is coming soon. These readings are recorded by '
              'our team until your inverter is connected.',
              style: theme.textTheme.labelSmall?.copyWith(height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Live hero ──────────────────────────────────────────────────────────────

/// The headline: a sweep gauge over the brand gradient.
class _LiveHero extends StatelessWidget {
  const _LiveHero({required this.summary});

  final GenerationSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
      decoration: BoxDecoration(
        gradient: AppColors.brand,
        borderRadius: BorderRadius.circular(AppRadius.card + 4),
        boxShadow: [
          BoxShadow(
            color: AppColors.ember.withValues(alpha: 0.38),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              // A soft pulse would be noise here; a plain dot reads as "live"
              // without competing with the number below it.
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 7),
              Text(
                'LIVE NOW',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
              const Spacer(),
              Icon(Icons.sync_rounded,
                  size: 13, color: Colors.white.withValues(alpha: 0.85)),
              const SizedBox(width: 4),
              Text(
                fmtTime(summary.lastSyncedAt),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.92),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 178,
            width: 178,
            child: CustomPaint(
              painter: _GaugePainter(value: summary.utilisation),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      summary.currentKw.toStringAsFixed(2),
                      style: theme.textTheme.displaySmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'kW',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: Text(
              '${(summary.utilisation * 100).round()}% of '
              '${fmtKw(summary.capacityKw)} capacity',
              style: theme.textTheme.labelMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A 270° sweep gauge — an arc rather than a full ring, so the reading has a
/// clear start and end instead of looping back on itself.
class _GaugePainter extends CustomPainter {
  _GaugePainter({required this.value});

  final double value;

  static const _start = math.pi * 0.75;
  static const _sweep = math.pi * 1.5;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = size.width / 2 - 11;
    final arcRect = Rect.fromCircle(center: center, radius: radius);

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 13
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: 0.22);

    final progress = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 13
      ..strokeCap = StrokeCap.round
      ..color = Colors.white;

    canvas.drawArc(arcRect, _start, _sweep, false, track);
    if (value > 0) {
      canvas.drawArc(arcRect, _start, _sweep * value.clamp(0, 1), false,
          progress);
    }

    // Tick marks around the sweep give the arc a scale to be read against.
    final tick = Paint()
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: 0.35);
    for (var i = 0; i <= 10; i++) {
      final a = _start + _sweep * (i / 10);
      final outer = radius + 10;
      final inner = radius + 5;
      canvas.drawLine(
        center + Offset(math.cos(a) * inner, math.sin(a) * inner),
        center + Offset(math.cos(a) * outer, math.sin(a) * outer),
        tick,
      );
    }
  }

  @override
  bool shouldRepaint(_GaugePainter old) => old.value != value;
}

// ── Stats ──────────────────────────────────────────────────────────────────

class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.summary});

  final GenerationSummary summary;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _StatCard(
                icon: Icons.wb_sunny_rounded,
                label: 'Today',
                value: summary.todayKwh.toStringAsFixed(1),
                unit: 'kWh',
                tint: AppColors.ember,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                icon: Icons.calendar_month_rounded,
                label: 'This month',
                value: summary.monthKwh.toStringAsFixed(0),
                unit: 'kWh',
                tint: AppColors.info,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _StatCard(
                icon: Icons.all_inclusive_rounded,
                label: 'Lifetime',
                value: NumberFormat.compact(locale: 'en_IN').format(summary.lifetimeKwh),
                unit: 'kWh',
                tint: AppColors.violetTint,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                icon: Icons.eco_rounded,
                label: 'CO₂ saved',
                value: NumberFormat.compact(locale: 'en_IN').format(summary.co2SavedKg),
                unit: 'kg',
                tint: AppColors.success,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.unit,
    required this.tint,
  });

  final IconData icon;
  final String label;
  final String value;
  final String unit;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GlassCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: tint.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(icon, color: tint, size: 16),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: value,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: theme.textTheme.bodyLarge?.color,
                  ),
                ),
                TextSpan(text: '  $unit', style: theme.textTheme.labelSmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Week chart ─────────────────────────────────────────────────────────────

class _WeekCard extends StatelessWidget {
  const _WeekCard({required this.points});

  final List<GenerationPoint> points;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (points.isEmpty) {
      return GlassCard(
        child: Text('No readings yet.', style: theme.textTheme.bodySmall),
      );
    }

    final total = points.fold<double>(0, (s, p) => s + p.kwh);
    final avg = total / points.length;
    final best = points.reduce((a, b) => a.kwh > b.kwh ? a : b);

    return GlassCard(
      padding: const EdgeInsets.fromLTRB(14, 16, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _MiniFact(label: 'Total', value: '${total.toStringAsFixed(0)} kWh'),
              const SizedBox(width: 18),
              _MiniFact(label: 'Daily avg', value: '${avg.toStringAsFixed(1)} kWh'),
              const SizedBox(width: 18),
              _MiniFact(
                label: 'Best',
                value: fmtWeekday(best.day),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(height: 168, child: _AreaChart(points: points)),
        ],
      ),
    );
  }
}

class _MiniFact extends StatelessWidget {
  const _MiniFact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: theme.textTheme.labelSmall),
        const SizedBox(height: 1),
        Text(
          value,
          style: theme.textTheme.bodyMedium
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
      ],
    );
  }
}

/// A smoothed area line reads as a trend; the earlier bars read as a tally.
class _AreaChart extends StatelessWidget {
  const _AreaChart({required this.points});

  final List<GenerationPoint> points;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxY = points.map((p) => p.kwh).reduce(math.max);
    final minY = points.map((p) => p.kwh).reduce(math.min);

    // Headroom above and below so the curve never touches the frame.
    //
    // A FLAT WEEK HAS NO RANGE TO PAD. A system commissioned yesterday, or an
    // engineer who keyed in a row of zeros, gives maxY == minY == 0: the top
    // and bottom collapse onto each other, the grid interval below comes out as
    // 0, and fl_chart asserts on a non-positive interval — so the tab threw
    // where it should have drawn a flat line along the floor. A minimum span of
    // 1 kWh gives the chart something to divide.
    final rawTop = (maxY * 1.18).ceilToDouble();
    final bottom = math.max(0, (minY * 0.55)).toDouble();
    final top = rawTop - bottom < 1 ? bottom + 1 : rawTop;

    return LineChart(
      LineChartData(
        minY: bottom,
        maxY: top,
        borderData: FlBorderData(show: false),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: math.max(1, ((top - bottom) / 3).ceilToDouble()),
          getDrawingHorizontalLine: (_) => FlLine(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.07),
            strokeWidth: 1,
          ),
        ),
        titlesData: FlTitlesData(
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 26,
              interval: 1,
              getTitlesWidget: (v, _) {
                final i = v.toInt();
                if (i < 0 || i >= points.length) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    fmtWeekday(points[i].day),
                    style: theme.textTheme.labelSmall?.copyWith(fontSize: 10),
                  ),
                );
              },
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => AppColors.ember,
            getTooltipItems: (spots) => spots
                .map((s) => LineTooltipItem(
                      '${s.y.toStringAsFixed(1)} kWh',
                      const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ))
                .toList(),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            isCurved: true,
            curveSmoothness: 0.32,
            preventCurveOverShooting: true,
            barWidth: 3,
            gradient: const LinearGradient(
              colors: [AppColors.ember, AppColors.amber],
            ),
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, _, _, _) => FlDotCirclePainter(
                radius: 3.5,
                color: AppColors.amber,
                strokeWidth: 2,
                strokeColor: Colors.white,
              ),
            ),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppColors.ember.withValues(alpha: 0.32),
                  AppColors.amber.withValues(alpha: 0.02),
                ],
              ),
            ),
            spots: List.generate(
              points.length,
              (i) => FlSpot(i.toDouble(), points[i].kwh),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Impact ─────────────────────────────────────────────────────────────────

class _ImpactCard extends StatelessWidget {
  const _ImpactCard({required this.summary});

  final GenerationSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GlassCard(
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              gradient: AppColors.leaf,
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            child: const Icon(Icons.park_rounded, color: Colors.white),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Like planting ${summary.treesEquivalent.round()} trees',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 3),
                Text(
                  '${NumberFormat.decimalPattern('en_IN').format(summary.co2SavedKg.round())} kg '
                  'of CO₂ avoided since your system was commissioned.',
                  style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
