import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../../core/data/customer_repository.dart';
import '../../core/models/customer_models.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/page_scaffold.dart';
import '../../core/utils/errors.dart';
import '../../core/utils/date_format.dart';

/// Refer & Earn — share a code, collect loyalty points.
class ReferralScreen extends StatefulWidget {
  const ReferralScreen({super.key});

  @override
  State<ReferralScreen> createState() => _ReferralScreenState();
}

class _ReferralScreenState extends State<ReferralScreen> {
  late Future<ReferralSummary> _future;

  @override
  void initState() {
    super.initState();
    _future = context.read<CustomerRepository>().referrals();
  }

  Future<void> _refresh() async {
    setState(() {
      _future = context.read<CustomerRepository>().referrals();
    });
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: 'REFER & EARN',
      // Every other list screen in the app already pulls to refresh; this one
      // was the one place a customer whose referral just converted had to
      // leave the screen and come back to see it.
      child: RefreshIndicator(
        onRefresh: _refresh,
        color: AppColors.ember,
        child: FutureBuilder<ReferralSummary>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(color: AppColors.ember),
              );
            }

            if (snap.hasError) {
              return ErrorRetry(message: friendlyError(snap.error), onRetry: _refresh);
            }

            final data = snap.data;
            if (data == null) {
              // EmptyState carries its own scroll now, so pull-to-refresh works
              // without a second ListView around it.
              return EmptyState(
                icon: Icons.card_giftcard_outlined,
                title: 'Referrals unavailable',
                subtitle: 'Pull down to try again.',
                action: OutlinedButton.icon(
                  onPressed: _refresh,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Try again'),
                ),
              );
            }

            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: pageInsets(context),
              children: [
                _PointsCard(summary: data),
                const SizedBox(height: 16),
                _CodeCard(code: data.code),
                const SizedBox(height: 20),

                const SectionTitle('How it works'),
                GlassCard(
                  child: Column(
                    children: const [
                      _Step(
                        number: '1',
                        title: 'Share your code',
                        body: 'Send it to friends, family or neighbours.',
                      ),
                      _Step(
                        number: '2',
                        title: 'They enquire',
                        body: 'They mention your code when applying for solar.',
                      ),
                      _Step(
                        number: '3',
                        title: 'You earn points',
                        body:
                            'Points are credited as their project progresses, '
                            'with the full reward on installation.',
                        isLast: true,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),
                SectionTitle('Your referrals (${data.referrals.length})'),
                if (data.referrals.isEmpty)
                  GlassCard(
                    child: Text(
                      'No referrals yet — share your code to get started.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  )
                else
                  ...data.referrals.map(
                    (r) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _ReferralTile(referral: r),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _PointsCard extends StatelessWidget {
  const _PointsCard({required this.summary});

  final ReferralSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: AppColors.brand,
        borderRadius: BorderRadius.circular(AppRadius.card),
        boxShadow: [
          BoxShadow(
            color: AppColors.ember.withValues(alpha: 0.34),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'LOYALTY POINTS',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  NumberFormat.decimalPattern('en_IN').format(summary.totalPoints),
                  style: theme.textTheme.displaySmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${summary.convertedCount} of ${summary.referrals.length} '
                  'referrals installed',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.92),
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.workspace_premium_rounded,
            size: 54,
            color: Colors.white.withValues(alpha: 0.9),
          ),
        ],
      ),
    );
  }
}

class _CodeCard extends StatelessWidget {
  const _CodeCard({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Your referral code', style: theme.textTheme.labelSmall),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 13,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.ember.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    border: Border.all(
                      color: AppColors.ember.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Text(
                    code,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2,
                      color: AppColors.ember,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              IconButton.filled(
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.ember,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(48, 48),
                ),
                icon: const Icon(Icons.copy_rounded, size: 19),
                tooltip: 'Copy code',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: code));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Referral code copied')),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({
    required this.number,
    required this.title,
    required this.body,
    this.isLast = false,
  });

  final String number;
  final String title;
  final String body;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              gradient: AppColors.brand,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                number,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
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

class _ReferralTile extends StatelessWidget {
  const _ReferralTile({required this.referral});

  final Referral referral;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GlassCard(
      padding: const EdgeInsets.all(13),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: AppColors.ember.withValues(alpha: 0.14),
            child: Text(
              referral.name.isNotEmpty ? referral.name[0].toUpperCase() : '?',
              style: const TextStyle(
                color: AppColors.ember,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  referral.name,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  fmtDate(referral.referredOn),
                  style: theme.textTheme.labelSmall,
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              StatusChip(
                label: referral.status,
                gradient: referral.statusGradient,
                compact: true,
              ),
              const SizedBox(height: 5),
              Text(
                '+${referral.pointsEarned} pts',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: AppColors.success,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
