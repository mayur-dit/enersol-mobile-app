import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/data/customer_repository.dart';
import '../../core/models/customer_models.dart';
import '../../core/state/screen_refresh.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/date_format.dart';
import '../../core/utils/errors.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/page_scaffold.dart';
import '../documents/document_requests_screen.dart';

/// One job, end to end — every milestone, and what is holding it up.
///
/// ── Why this exists beside the Application tab ──────────────────────────────
/// That tab lists a customer's applications and summarises each. This is the
/// drill-down: the FULL ladder for one job, including the client-application
/// (DISCOM) steps, with any document we are waiting for shown AGAINST THE
/// MILESTONE IT IS BLOCKING rather than in a list of its own.
///
/// That pairing is the whole idea. "We need your electricity bill" is a chore.
/// "We need your electricity bill, and it is the only thing between you and the
/// feasibility approval" is a reason — and people act on reasons. It is also
/// the honest answer to the question this screen exists to answer, which is
/// never "what stage is it at" but always "why has it not moved".
class ProjectProgressScreen extends StatefulWidget {
  const ProjectProgressScreen({super.key, required this.application});

  final SolarApplication application;

  @override
  State<ProjectProgressScreen> createState() => _ProjectProgressScreenState();
}

class _ProjectProgressScreenState extends State<ProjectProgressScreen>
    with ScreenRefresh {
  late Future<(SolarApplication, List<DocumentRequest>)> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  /// Re-reads the application as well as the requests.
  ///
  /// The card that opened this screen may have been minutes old, and this is
  /// the screen somebody opens BECAUSE they have just been told something
  /// moved — showing them the stale copy they tapped would be the one place the
  /// app contradicts its own notification.
  Future<(SolarApplication, List<DocumentRequest>)> _load() async {
    final repo = context.read<CustomerRepository>();

    // THE LADDER IS THE SCREEN; the blockers are an annotation on it. A
    // `Future.wait` over both fails the pair the moment either throws, so a
    // document-requests read that errored took the customer's whole progress
    // view with it and answered "why has my project not moved?" with
    // "Couldn't load". An empty blocker list simply drops the banner.
    final fetched = repo.applications();
    final requests = repo
        .documentRequests(projectId: widget.application.projectId ?? '')
        .catchError((_) => const <DocumentRequest>[]);

    final apps = await fetched;
    final fresh = apps
            .where((a) => a.reference == widget.application.reference)
            .firstOrNull ??
        widget.application;
    return (fresh, await requests);
  }

  @override
  Future<void> loadData() async {
    setState(() {
      _future = _load();
    });
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: 'PROJECT PROGRESS',
      child: RefreshIndicator(
        onRefresh: refreshNow,
        color: AppColors.ember,
        child: FutureBuilder<(SolarApplication, List<DocumentRequest>)>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return ErrorRetry(
                message: friendlyError(snap.error),
                onRetry: refreshNow,
              );
            }

            final app = snap.data?.$1 ?? widget.application;
            final requests = snap.data?.$2 ?? const <DocumentRequest>[];
            final outstanding = requests.where((r) => r.needsAction).toList();

            // Requests keyed by the step they name, so a milestone can carry
            // its own blockers. Requests naming no step fall through to the
            // "anything else" block below rather than being dropped.
            final byStep = <String, List<DocumentRequest>>{};
            for (final r in outstanding) {
              if (r.stepKey.isEmpty) continue;
              byStep.putIfAbsent(r.stepKey, () => []).add(r);
            }
            final unattached =
                outstanding.where((r) => r.stepKey.isEmpty).toList();

            final groups = <String, List<AppStage>>{};
            for (final s in app.stages) {
              groups.putIfAbsent(s.group.isEmpty ? 'Progress' : s.group, () => [])
                  .add(s);
            }

            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: pageInsets(context),
              children: [
                _Header(application: app),
                const SizedBox(height: 14),

                // What is being waited on, said once at the top with a way to
                // act on it. Somebody who opens this screen because their job
                // has not moved should not have to scroll a ladder to find out
                // that the answer is "you".
                if (outstanding.isNotEmpty) ...[
                  _BlockedBanner(
                    count: outstanding.length,
                    onOpen: () => _openRequests(app),
                  ),
                  const SizedBox(height: 14),
                ],

                for (final entry in groups.entries) ...[
                  SectionTitle(entry.key),
                  ...entry.value.asMap().entries.map(
                        (e) => _StageRow(
                          stage: e.value,
                          isLast: e.key == entry.value.length - 1,
                          blockers: byStep[e.value.key] ?? const [],
                          onOpenRequest: (r) => _openRequests(app, highlight: r),
                        ),
                      ),
                  const SizedBox(height: 6),
                ],

                if (unattached.isNotEmpty) ...[
                  const SectionTitle('Also needed from you'),
                  ...unattached.map(
                    (r) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _BlockerTile(
                        request: r,
                        onTap: () => _openRequests(app, highlight: r),
                      ),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _openRequests(
    SolarApplication app, {
    DocumentRequest? highlight,
  }) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DocumentRequestsScreen(
          projectId: app.projectId,
          highlightId: highlight?.id,
        ),
      ),
    );
    if (mounted) await refreshNow();
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.application});

  final SolarApplication application;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final a = application;

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(a.projectName ?? a.reference,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text(a.reference, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              StatusChip(label: a.status, gradient: a.statusGradient),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: LinearProgressIndicator(
              value: a.progress,
              minHeight: 8,
              backgroundColor:
                  theme.colorScheme.onSurface.withValues(alpha: 0.10),
              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.ember),
            ),
          ),
          const SizedBox(height: 9),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Now: ${a.currentLabel}',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                '${a.completedCount} of ${a.stages.length} done',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
          if (a.siteAddress != null || a.capacityKw > 0) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 6,
              children: [
                if (a.capacityKw > 0)
                  _Fact(
                    icon: Icons.solar_power_rounded,
                    text: '${a.capacityKw} kW',
                  ),
                if (a.discom != null)
                  _Fact(icon: Icons.bolt_rounded, text: a.discom!),
                if (a.siteAddress != null)
                  _Fact(icon: Icons.place_rounded, text: a.siteAddress!),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppColors.ember),
        const SizedBox(width: 5),
        Text(text, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _BlockedBanner extends StatelessWidget {
  const _BlockedBanner({required this.count, required this.onOpen});

  final int count;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassCard(
      onTap: onOpen,
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              gradient: AppColors.brand,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: const Icon(Icons.pending_actions_rounded,
                color: Colors.white, size: 21),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  count == 1
                      ? 'We are waiting on 1 document'
                      : 'We are waiting on $count documents',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(
                  'Sending them is what moves the steps below on.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded),
        ],
      ),
    );
  }
}

/// One milestone of the ladder, with its blockers underneath it.
class _StageRow extends StatelessWidget {
  const _StageRow({
    required this.stage,
    required this.isLast,
    required this.blockers,
    required this.onOpenRequest,
  });

  final AppStage stage;
  final bool isLast;
  final List<DocumentRequest> blockers;
  final ValueChanged<DocumentRequest> onOpenRequest;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final done = stage.state == StageState.done;
    final current = stage.state == StageState.current;

    final dotColour = done
        ? AppColors.success
        : current
            ? AppColors.ember
            : theme.dividerColor;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The rail: a dot per milestone and a line joining them, so the
          // ladder reads as one journey rather than as a list of chips.
          Column(
            children: [
              Container(
                width: 16,
                height: 16,
                margin: const EdgeInsets.only(top: 3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: done || current ? dotColour : Colors.transparent,
                  border: Border.all(color: dotColour, width: 2),
                ),
                child: done
                    ? const Icon(Icons.check_rounded,
                        size: 10, color: Colors.white)
                    : null,
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 3),
                    color: done ? AppColors.success : theme.dividerColor,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    stage.label,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: current ? FontWeight.w800 : FontWeight.w600,
                      color: stage.state == StageState.pending
                          ? theme.textTheme.bodySmall?.color
                          : null,
                    ),
                  ),
                  if (stage.date != null)
                    Text(fmtDate(stage.date),
                        style: theme.textTheme.labelSmall),
                  if (stage.note != null && stage.note!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(stage.note!,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(height: 1.35)),
                    ),
                  // What this particular step is waiting on. Attached HERE
                  // rather than collected into a separate list, because the
                  // pairing is the explanation.
                  ...blockers.map(
                    (r) => Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: _BlockerTile(
                        request: r,
                        onTap: () => onOpenRequest(r),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BlockerTile extends StatelessWidget {
  const _BlockerTile({required this.request, required this.onTap});

  final DocumentRequest request;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final overdue = request.isOverdue;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: (overdue ? AppColors.danger : AppColors.ember)
              .withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: (overdue ? AppColors.danger : AppColors.ember)
                .withValues(alpha: 0.35),
          ),
        ),
        child: Row(
          children: [
            Icon(
              overdue
                  ? Icons.error_outline_rounded
                  : Icons.upload_file_rounded,
              size: 17,
              color: overdue ? AppColors.danger : AppColors.ember,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    request.title,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    request.dueDate == null
                        ? 'Tap to upload'
                        : overdue
                            ? 'Was due ${fmtDate(request.dueDate)} — tap to upload'
                            : 'By ${fmtDate(request.dueDate)} — tap to upload',
                    style: theme.textTheme.labelSmall,
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, size: 18),
          ],
        ),
      ),
    );
  }
}
