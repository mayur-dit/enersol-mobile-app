import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/data/customer_repository.dart';
import '../../core/models/customer_models.dart';
import '../../core/state/screen_refresh.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/app_shell.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/page_scaffold.dart';
import '../../shared/widgets/segmented_tabs.dart';
import '../../core/utils/errors.dart';
import '../../core/utils/date_format.dart';

/// Warranty cards and the rest of the paperwork, available once the
/// installation is commissioned.
class DocumentsScreen extends StatefulWidget {
  const DocumentsScreen({super.key});

  @override
  State<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends State<DocumentsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.page,
            AppSpacing.md,
            AppSpacing.page,
            AppSpacing.xs,
          ),
          child: SegmentedTabs(
            controller: _tabs,
            labels: const ['Warranty', 'Other Documents'],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: const [
              _DocumentList(kind: _DocKind.warranty),
              _DocumentList(kind: _DocKind.other),
            ],
          ),
        ),
      ],
    );
  }
}

enum _DocKind { warranty, other }

class _DocumentList extends StatefulWidget {
  const _DocumentList({required this.kind});

  final _DocKind kind;

  @override
  State<_DocumentList> createState() => _DocumentListState();
}

class _DocumentListState extends State<_DocumentList>
    with AutomaticKeepAliveClientMixin, ScreenRefresh {
  late Future<List<CustomerDocument>> _future;

  @override
  bool get wantKeepAlive => true;

  /// Publishing a document is the office's most common reason to notify this
  /// customer, and this list is where that notification sends them.
  @override
  int? get refreshTab => ShellTab.docs;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<CustomerDocument>> _load() {
    final repo = context.read<CustomerRepository>();
    return widget.kind == _DocKind.warranty
        ? repo.warrantyDocuments()
        : repo.otherDocuments();
  }

  @override
  Future<void> loadData() async {
    // Block body — see the note in home_screen: an arrow closure returns the
    // assigned Future and setState asserts on that.
    setState(() {
      _future = _load();
    });
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return RefreshIndicator(
      onRefresh: refreshNow,
      color: AppColors.ember,
      child: FutureBuilder<List<CustomerDocument>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.ember),
            );
          }
          if (snap.hasError) {
            return ErrorRetry(
              message: friendlyError(snap.error),
              onRetry: refreshNow,
            );
          }

          final docs = snap.data ?? const <CustomerDocument>[];
          if (docs.isEmpty) {
            return EmptyState(
              icon: widget.kind == _DocKind.warranty
                  ? Icons.verified_outlined
                  : Icons.folder_open_outlined,
              title: 'No documents yet',
              subtitle: widget.kind == _DocKind.warranty
                  ? 'Warranty cards are issued once your installation is '
                      'commissioned.'
                  : 'Government and personal documents appear here after '
                      'commissioning.',
            );
          }

          // Group by category so each warranty type gets its own heading.
          final grouped = <String, List<CustomerDocument>>{};
          for (final d in docs) {
            grouped.putIfAbsent(d.category, () => []).add(d);
          }

          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: tabInsets(context),
            children: [
              for (final entry in grouped.entries) ...[
                SectionTitle(entry.key),
                ...entry.value.map(
                  (d) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _DocumentTile(document: d),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _DocumentTile extends StatelessWidget {
  const _DocumentTile({required this.document});

  final CustomerDocument document;

  /// Open (and, for anything the phone cannot render, download) the file.
  ///
  /// TWO MODES, IN ORDER. `externalApplication` hands the URL to whatever the
  /// phone uses for PDFs or to the browser, which is what actually saves the
  /// file to Downloads — the behaviour a customer means by "download my warranty
  /// card". It can fail outright on a device with no matching app and, on some
  /// Android builds, on a URL with a query string, so the in-app browser is the
  /// fallback rather than an error message: a document the customer can read on
  /// screen beats a snackbar telling them their phone is not set up.
  Future<void> _open(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);

    if (!document.isDownloadable) {
      messenger.showSnackBar(
        const SnackBar(content: Text('This document is not available yet.')),
      );
      return;
    }

    final uri = Uri.tryParse(document.url!);
    // A relative path can no longer reach here (the repository absolutises
    // every URL), but a hand-typed link in the admin panel still can.
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      messenger.showSnackBar(
        const SnackBar(content: Text('That link looks broken. Please tell us.')),
      );
      return;
    }

    var ok = false;
    try {
      ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      ok = false;
    }
    if (ok) return;

    try {
      ok = await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
    } catch (_) {
      ok = false;
    }
    if (!ok) {
      messenger.showSnackBar(
        const SnackBar(content: Text('No app available to open this file.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final expired = document.validUntil != null &&
        document.validUntil!.isBefore(DateTime.now());

    return GlassCard(
      padding: const EdgeInsets.all(13),
      onTap: () => _open(context),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              gradient: expired ? AppColors.rose : AppColors.sky,
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
            child: const Icon(Icons.picture_as_pdf_rounded,
                color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  document.title,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 3),
                Text(
                  [
                    'Issued ${fmtDate(document.issuedOn)}',
                    if (document.sizeLabel != null) document.sizeLabel!,
                  ].join('  ·  '),
                  style: theme.textTheme.labelSmall,
                ),
                if (document.validUntil != null) ...[
                  const SizedBox(height: 5),
                  StatusChip(
                    compact: true,
                    label: expired
                        ? 'Expired'
                        : 'Valid till '
                            '${fmtMonthYear(document.validUntil)}',
                    gradient: expired ? AppColors.rose : AppColors.leaf,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            Icons.download_rounded,
            size: 21,
            color: document.isDownloadable
                ? AppColors.ember
                : theme.textTheme.labelSmall?.color,
          ),
        ],
      ),
    );
  }
}
