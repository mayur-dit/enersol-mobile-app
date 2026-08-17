import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/data/customer_repository.dart';
import '../../core/models/customer_models.dart';
import '../../core/state/auth_service.dart';
import '../../core/state/screen_refresh.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/page_scaffold.dart';
import '../../shared/widgets/app_shell.dart';
import '../application/project_progress_screen.dart';
import '../referral/referral_screen.dart';
import '../../core/utils/errors.dart';
import '../../core/utils/date_format.dart';

/// The landing tab: who you are, where your project stands, and the quickest
/// route into everything else.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.onNavigate});

  /// Switches the shell's footer tab — used by the quick-action tiles.
  final ValueChanged<int> onNavigate;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with ScreenRefresh {
  late Future<(List<SolarApplication>, GenerationSummary?)> _future;

  /// The landing tab, and the one most likely to be on screen when news lands.
  @override
  int? get refreshTab => ShellTab.home;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<(List<SolarApplication>, GenerationSummary?)> _load() async {
    final repo = context.read<CustomerRepository>();
    // Generation is absent until a system is commissioned and syncing, so it is
    // fetched alongside rather than gating the rest of the screen.
    final results = await Future.wait([repo.applications(), repo.generation()]);
    return (
      results[0] as List<SolarApplication>,
      results[1] as GenerationSummary?,
    );
  }

  @override
  Future<void> loadData() async {
    // A block body, not `setState(() => _future = …)`: an arrow closure
    // RETURNS the Future it just assigned, and setState asserts on a callback
    // that hands one back.
    setState(() {
      _future = _load();
    });
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthService>().user;
    final theme = Theme.of(context);

    return RefreshIndicator(
      onRefresh: refreshNow,
      color: AppColors.ember,
      child: FutureBuilder<(List<SolarApplication>, GenerationSummary?)>(
        future: _future,
        builder: (context, snap) {
          final loading = snap.connectionState == ConnectionState.waiting;

          // A FAILED LOAD IS NOT AN EMPTY ONE. Without this branch the screen
          // fell through with no applications and drew "You have no active
          // application — start one", which tells a customer with a live
          // project on a bad connection that their project does not exist.
          if (!loading && snap.hasError) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                16,
                60,
                16,
                shellBottomInset(context, extra: 24),
              ),
              children: [
                ErrorRetry(message: friendlyError(snap.error), onRetry: refreshNow),
              ],
            );
          }

          final apps = snap.data?.$1 ?? const <SolarApplication>[];
          final gen = snap.data?.$2;
          final active = apps.where((a) => a.status != 'Completed').firstOrNull;
          final confirmed = apps.where((a) => a.isConfirmed).length;
          final completed =
              apps.where((a) => a.status == 'Completed' || a.status == 'Closed').length;

          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: tabInsets(context, extra: 24),
            children: [
              // ── Greeting ────────────────────────────────────────────────
              Text(
                _greeting(),
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 2),
              Text(
                user?.name ?? 'Customer',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 18),

              if (loading)
                const _HomeSkeleton()
              else ...[
                // ── At a glance ───────────────────────────────────────────
                if (apps.isNotEmpty) ...[
                  Row(
                    children: [
                      Expanded(
                        child: _GlanceTile(
                          icon: Icons.description_rounded,
                          value: '${apps.length}',
                          label: apps.length == 1 ? 'Application' : 'Applications',
                          gradient: AppColors.sky,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _GlanceTile(
                          icon: Icons.verified_rounded,
                          value: '$confirmed',
                          label: 'Confirmed',
                          gradient: AppColors.brand,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _GlanceTile(
                          icon: Icons.check_circle_rounded,
                          value: '$completed',
                          label: 'Completed',
                          gradient: AppColors.leaf,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],

                // ── Active project ────────────────────────────────────────
                //
                // Tapping opens the FULL progress of that one job — every
                // milestone including the DISCOM steps, and whatever we are
                // waiting on from them. It used to switch to the Applications
                // tab, which answered "which jobs do I have" when the person
                // tapping a progress bar is asking "why has this one not moved".
                if (active != null)
                  _ActiveProjectCard(
                    application: active,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ProjectProgressScreen(application: active),
                      ),
                    ),
                  )
                else
                  _NoProjectCard(onApply: () => widget.onNavigate(ShellTab.apply)),

                const SizedBox(height: 16),

                // ── Generation snapshot ───────────────────────────────────
                if (gen != null) ...[
                  const SectionTitle('Your generation'),
                  _GenerationStrip(
                    summary: gen,
                    onTap: () => widget.onNavigate(ShellTab.power),
                  ),
                  const SizedBox(height: 16),
                ],

                // ── Quick actions ─────────────────────────────────────────
                const SectionTitle('Quick actions'),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.55,
                  children: [
                    _ActionTile(
                      icon: Icons.add_home_work_rounded,
                      label: 'New Application',
                      caption: 'Apply for solar',
                      gradient: AppColors.brand,
                      onTap: () => widget.onNavigate(ShellTab.apply),
                    ),
                    _ActionTile(
                      icon: Icons.folder_rounded,
                      label: 'Documents',
                      caption: 'Warranty & papers',
                      gradient: AppColors.sky,
                      onTap: () => widget.onNavigate(ShellTab.docs),
                    ),
                    _ActionTile(
                      icon: Icons.build_rounded,
                      label: 'Service',
                      caption: 'Raise a request',
                      gradient: AppColors.violet,
                      onTap: () => widget.onNavigate(ShellTab.service),
                    ),
                    _ActionTile(
                      icon: Icons.card_giftcard_rounded,
                      label: 'Refer & Earn',
                      caption: 'Earn loyalty points',
                      gradient: AppColors.leaf,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const ReferralScreen(),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning,';
    if (h < 17) return 'Good afternoon,';
    return 'Good evening,';
  }
}

// ── Active project ─────────────────────────────────────────────────────────

class _ActiveProjectCard extends StatelessWidget {
  const _ActiveProjectCard({required this.application, required this.onTap});

  final SolarApplication application;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Current project',
                      style: theme.textTheme.labelSmall,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      application.reference,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              StatusChip(
                label: application.status,
                gradient: application.statusGradient,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _Metric(
                icon: Icons.solar_power_rounded,
                label: 'Capacity',
                value: '${application.capacityKw} kW',
              ),
              const SizedBox(width: 18),
              if (application.expectedCompletion != null)
                _Metric(
                  icon: Icons.event_rounded,
                  label: 'Expected',
                  value: fmtDate(application.expectedCompletion),
                ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: LinearProgressIndicator(
              value: application.progress,
              minHeight: 7,
              backgroundColor:
                  theme.colorScheme.onSurface.withValues(alpha: 0.10),
              valueColor:
                  const AlwaysStoppedAnimation<Color>(AppColors.ember),
            ),
          ),
          const SizedBox(height: 9),
          Row(
            children: [
              Expanded(
                child: Text(
                  // The card's own headline, which falls back to the stage name
                  // the server sent — a job whose timeline has nothing marked
                  // "current" used to claim every milestone was complete, which
                  // for a brand-new enquiry is the opposite of the truth.
                  'Now: ${application.currentLabel}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                '${(application.progress * 100).round()}%',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: AppColors.ember,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NoProjectCard extends StatelessWidget {
  const _NoProjectCard({required this.onApply});

  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.wb_sunny_rounded,
                  color: AppColors.ember, size: 22),
              const SizedBox(width: 9),
              Text(
                'Go solar',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'You have no active application. Start one and our team will '
            'survey your rooftop and share a proposal.',
            style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
          ),
          const SizedBox(height: 16),
          GradientButton(
            label: 'Apply for solar',
            icon: Icons.arrow_forward_rounded,
            height: 46,
            onPressed: onApply,
          ),
        ],
      ),
    );
  }
}

// ── Generation strip ───────────────────────────────────────────────────────

class _GenerationStrip extends StatelessWidget {
  const _GenerationStrip({required this.summary, required this.onTap});

  final GenerationSummary summary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GlassCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              gradient: AppColors.brand,
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            child: const Icon(Icons.bolt_rounded, color: Colors.white),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _MiniStat(
                  label: 'Today',
                  value: summary.todayKwh.toStringAsFixed(1),
                  unit: 'kWh',
                ),
                _MiniStat(
                  label: 'Month',
                  value: summary.monthKwh.toStringAsFixed(0),
                  unit: 'kWh',
                ),
                _MiniStat(
                  label: 'Now',
                  value: summary.currentKw.toStringAsFixed(1),
                  unit: 'kW',
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded,
              color: theme.textTheme.bodySmall?.color),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.label,
    required this.value,
    required this.unit,
  });

  final String label;
  final String value;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: theme.textTheme.labelSmall),
        const SizedBox(height: 2),
        RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text: value,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              TextSpan(
                text: ' $unit',
                style: theme.textTheme.labelSmall,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 17, color: theme.textTheme.bodySmall?.color),
        const SizedBox(width: 7),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: theme.textTheme.labelSmall),
            Text(
              value,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ],
    );
  }
}

// ── Quick action tile ──────────────────────────────────────────────────────

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.caption,
    required this.gradient,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String caption;
  final LinearGradient gradient;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GlassCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              gradient: gradient,
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
            child: Icon(icon, color: Colors.white, size: 19),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              Text(
                caption,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A compact count tile for the "at a glance" row.
class _GlanceTile extends StatelessWidget {
  const _GlanceTile({
    required this.icon,
    required this.value,
    required this.label,
    required this.gradient,
  });

  final IconData icon;
  final String value;
  final String label;
  final LinearGradient gradient;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              gradient: gradient,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Icon(icon, color: Colors.white, size: 16),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              height: 1,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall,
          ),
        ],
      ),
    );
  }
}

class _HomeSkeleton extends StatelessWidget {
  const _HomeSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(
        3,
        (i) => Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: GlassCard(
            child: SizedBox(
              height: i == 0 ? 118 : 62,
              child: const Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: AppColors.ember,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
