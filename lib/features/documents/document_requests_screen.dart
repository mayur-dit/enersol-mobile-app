import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/env.dart';
import '../../core/data/customer_repository.dart';
import '../../core/models/customer_models.dart';
import '../../core/models/picked_upload.dart';
import '../../core/state/screen_refresh.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/date_format.dart';
import '../../core/utils/errors.dart';
import '../../shared/widgets/confirm_dialog.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/page_scaffold.dart';

/// What the office is waiting on FROM this customer.
///
/// ── Why this is a screen and not a section of Documents ─────────────────────
/// The Documents tab is an archive: things we have given them, which they open
/// when they need one. This is a TO-DO LIST — every row is something they have
/// to do, and mixing the two would bury the four rows that matter under forty
/// that do not.
///
/// ── Opened from a notification, usually ─────────────────────────────────────
/// The whole point of the feature is that "we need your electricity bill"
/// arrives as a tap that lands here with the upload button already in front of
/// them. A notification that only announces a need and leaves somebody hunting
/// for where to satisfy it is how a request sits open for a fortnight.
///
/// [highlightId] scrolls to and opens one particular request — what the
/// notification passes.
class DocumentRequestsScreen extends StatefulWidget {
  const DocumentRequestsScreen({super.key, this.projectId, this.highlightId});

  /// Narrow to one job. Absent shows everything outstanding for this customer.
  final String? projectId;

  /// Open this request's sheet on arrival — the notification's destination.
  final String? highlightId;

  @override
  State<DocumentRequestsScreen> createState() => _DocumentRequestsScreenState();
}

class _DocumentRequestsScreenState extends State<DocumentRequestsScreen>
    with ScreenRefresh {
  late Future<List<DocumentRequest>> _future;
  bool _openedHighlight = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<DocumentRequest>> _load() {
    return context.read<CustomerRepository>().documentRequests(
      projectId: widget.projectId,
    );
  }

  @override
  Future<void> loadData() async {
    setState(() {
      _future = _load();
    });
    await _future;
  }

  /// Open the request a notification pointed at, once its row exists.
  void _maybeOpenHighlight(List<DocumentRequest> list) {
    final id = widget.highlightId;
    if (_openedHighlight || id == null || id.isEmpty) return;
    final match = list.where((r) => r.id == id).firstOrNull;
    if (match == null) return;
    _openedHighlight = true;
    // After the frame: opening a sheet from inside build() throws, and this is
    // reached during a FutureBuilder's builder.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _openSheet(match);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PageScaffold(
      title: 'Documents Needed',
      child: RefreshIndicator(
        onRefresh: refreshNow,
        color: AppColors.ember,
        child: FutureBuilder<List<DocumentRequest>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            // A FAILED LOAD IS NOT AN EMPTY ONE — telling somebody with four
            // outstanding requests that they have none is worse than an error.
            if (snap.hasError) {
              return ErrorRetry(
                message: friendlyError(snap.error),
                onRetry: refreshNow,
              );
            }

            final all = snap.data ?? const <DocumentRequest>[];
            _maybeOpenHighlight(all);

            if (all.isEmpty) {
              return const EmptyState(
                icon: Icons.task_alt_rounded,
                title: 'Nothing needed from you',
                subtitle:
                    'When we need a document to move your application on, it will '
                    'appear here and we will send you an alert.',
              );
            }

            final todo = all.where((r) => r.needsAction).toList();
            final sent = all.where((r) => r.awaitingReview).toList();
            final done = all
                .where((r) => !r.needsAction && !r.awaitingReview)
                .toList();

            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: pageInsets(context),
              children: [
                if (todo.isNotEmpty) ...[
                  _Banner(count: todo.length),
                  const SizedBox(height: 14),
                  ...todo.map(
                    (r) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _RequestCard(
                        request: r,
                        onTap: () => _openSheet(r),
                      ),
                    ),
                  ),
                ],
                if (sent.isNotEmpty) ...[
                  const SectionTitle('Sent, waiting on us'),
                  ...sent.map(
                    (r) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _RequestCard(
                        request: r,
                        onTap: () => _openSheet(r),
                      ),
                    ),
                  ),
                ],
                if (done.isNotEmpty) ...[
                  const SectionTitle('Done'),
                  ...done.map(
                    (r) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _RequestCard(
                        request: r,
                        onTap: () => _openSheet(r),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  'Photographs are fine — just make sure the whole page is in '
                  'frame and the text is readable.',
                  style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _openSheet(DocumentRequest request) async {
    final sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _UploadSheet(request: request),
    );
    if (sent == true && mounted) await refreshNow();
  }
}

/// The one-line summary above the list — what is outstanding, in plain words.
class _Banner extends StatelessWidget {
  const _Banner({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassCard(
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              gradient: AppColors.brand,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: const Icon(
              Icons.upload_file_rounded,
              color: Colors.white,
              size: 21,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  count == 1 ? '1 document needed' : '$count documents needed',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Sending these is what lets us move your application on.',
                  style: theme.textTheme.bodySmall?.copyWith(height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({required this.request, required this.onTap});

  final DocumentRequest request;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = request;

    return GlassCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  r.title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              StatusChip(
                label: r.needsAction && r.status == 'Rejected'
                    ? 'Send again'
                    : r.status,
                gradient: r.toneGradient,
                compact: true,
              ),
            ],
          ),
          if (r.description.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              r.description,
              style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
            ),
          ],
          // The step this unblocks. "We need your electricity bill" is a
          // sentence; "…and it is what is holding up the DISCOM feasibility
          // check" is an explanation, and people act on explanations.
          if (r.stepName.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(
                  Icons.route_rounded,
                  size: 14,
                  color: AppColors.ember,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Needed for: ${r.stepName}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
          // The desk's reason for sending it back — the whole point of a
          // Rejected row, and useless if the customer has to guess at it.
          if (r.reviewNote.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.info_outline_rounded,
                    size: 15,
                    color: AppColors.danger,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      r.reviewNote,
                      style: theme.textTheme.bodySmall?.copyWith(height: 1.35),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              if (r.dueDate != null) ...[
                Icon(
                  Icons.event_rounded,
                  size: 14,
                  color: r.isOverdue ? AppColors.danger : null,
                ),
                const SizedBox(width: 5),
                Text(
                  r.isOverdue
                      ? 'Was due ${fmtDate(r.dueDate)}'
                      : 'By ${fmtDate(r.dueDate)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: r.isOverdue ? AppColors.danger : null,
                    fontWeight: r.isOverdue ? FontWeight.w700 : null,
                  ),
                ),
                const SizedBox(width: 14),
              ],
              if (r.files.isNotEmpty) ...[
                const Icon(Icons.attach_file_rounded, size: 14),
                const SizedBox(width: 5),
                Text('${r.files.length}', style: theme.textTheme.bodySmall),
              ],
              const Spacer(),
              if (r.needsAction)
                Text(
                  'Upload',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: AppColors.ember,
                    fontWeight: FontWeight.w800,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Pick files, add a note, send.
///
/// THREE WAYS IN, because the paper being asked for arrives three ways: it is
/// already a photo in the gallery, it is on the desk and needs photographing,
/// or it is a PDF somebody was emailed. Offering only one of those means the
/// other two get sent on WhatsApp instead and the request stays open.
class _UploadSheet extends StatefulWidget {
  const _UploadSheet({required this.request});

  final DocumentRequest request;

  @override
  State<_UploadSheet> createState() => _UploadSheetState();
}

class _UploadSheetState extends State<_UploadSheet> {
  final List<PickedUpload> _picked = [];
  final TextEditingController _note = TextEditingController();
  bool _sending = false;
  String? _error;

  /// How many files this request will hold once these are sent.
  ///
  /// Already-received files COUNT: the server merges rather than replaces, so
  /// a customer answering "all three pages" who has already sent two owes one.
  int get _totalAfterSend => widget.request.files.length + _picked.length;

  /// Files still owed against `minFiles`, which nothing enforced before.
  ///
  /// The office sets it when one page is not the whole answer — both sides of
  /// a sanction letter, every page of a bill. Without it the customer sent one
  /// page, the request went to Submitted, the desk rejected it, and a day went
  /// on a round trip the screen could have prevented.
  int get _shortBy {
    final owed = widget.request.minFiles - _totalAfterSend;
    return owed < 0 ? 0 : owed;
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  /// Take the picks, or say why there are none.
  ///
  /// A picker can hand back a row the app cannot read — no bytes and no path,
  /// which is what a failed platform read looks like. Dropping those silently
  /// left the customer pressing a button that did nothing.
  void _accept(List<PickedUpload?> picks) {
    final usable = picks.whereType<PickedUpload>().toList();
    if (!mounted) return;
    setState(() {
      if (usable.isEmpty) {
        _error = 'That file could not be read. Try another one.';
      } else {
        _error = null;
        _picked.addAll(usable);
      }
    });
  }

  Future<void> _pick(Future<List<PickedUpload?>> Function() choose) async {
    try {
      final picks = await choose();
      if (picks.isEmpty) return; // Cancelled — not a failure.
      _accept(picks);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  Future<void> _addFromCamera() => _pick(() async {
        final shot = await ImagePicker().pickImage(
          source: ImageSource.camera,
          // Capped on the way in rather than after the transfer: a
          // 12-megapixel photograph of an A4 page is no more readable than a
          // 2-megapixel one and costs a customer on mobile data four times as
          // much to send.
          maxWidth: 2400,
          imageQuality: 82,
        );
        if (shot == null) return const [];
        return [await PickedUpload.fromXFile(shot)];
      });

  Future<void> _addFromGallery() => _pick(() async {
        final shots = await ImagePicker().pickMultiImage(
          maxWidth: 2400,
          imageQuality: 82,
        );
        return [
          for (final shot in shots) await PickedUpload.fromXFile(shot),
        ];
      });

  Future<void> _addFile() => _pick(() async {
        // file_picker 11 exposes `pickFiles` as a static; the `.platform`
        // accessor was the v8 API.
        //
        // `withData` ONLY on the web: there it is the only way to get at the
        // contents, while on a phone it would pull a 100MB scan into memory
        // that the uploader would otherwise have streamed off disk.
        final result = await FilePicker.pickFiles(
          allowMultiple: true,
          withData: kIsWeb,
          type: FileType.custom,
          allowedExtensions: const [
            'pdf',
            'jpg',
            'jpeg',
            'png',
            'webp',
            'doc',
            'docx',
          ],
        );
        return (result?.files ?? const <PlatformFile>[])
            .map(PickedUpload.fromPlatformFile)
            .toList();
      });

  /// Back out of the sheet, but not out of a send and not out of a stack of
  /// files the customer has just spent a minute choosing.
  Future<void> _back() async {
    final navigator = Navigator.of(context);

    if (_sending) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sending your files — one moment.')),
      );
      return;
    }

    if (_picked.isEmpty) {
      navigator.pop();
      return;
    }

    final discard = await confirmAction(
      context,
      icon: Icons.delete_outline_rounded,
      title: 'Discard these files?',
      message: _picked.length == 1
          ? 'The file you picked has not been sent yet.'
          : 'The ${_picked.length} files you picked have not been sent yet.',
      cancelLabel: 'Keep',
      confirmLabel: 'Discard',
      confirmColor: AppColors.danger,
    );
    if (discard) navigator.pop();
  }

  Future<void> _send() async {
    if (_picked.isEmpty) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await context.read<CustomerRepository>().submitDocumentRequest(
        requestId: widget.request.id,
        files: _picked,
        note: _note.text,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _sending = false;
          _error = friendlyError(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = widget.request;
    final canSend = _picked.isNotEmpty && !_sending && _shortBy == 0;

    // A SEND IN PROGRESS MUST NOT BE SWIPED AWAY. The transfer keeps going
    // after the sheet closes, but the list behind it never refreshes and the
    // customer is left looking at "1 document needed" for something they just
    // sent — so they send it again. Blocks the barrier tap and the back gesture
    // for the seconds it takes, and says WHY rather than just ignoring the
    // press — see [_back].
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Padding(
        // Lifts the sheet clear of the keyboard when the note field has focus.
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: GlassCard(
          strong: true,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppRadius.xl),
          ),
          padding: EdgeInsets.fromLTRB(
            18,
            14,
            18,
            MediaQuery.viewPaddingOf(context).bottom + 18,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: theme.dividerColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  r.title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (r.description.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    r.description,
                    style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
                  ),
                ],

                // What has already been filed against this request, from either
                // side. Shown so somebody does not send the same page twice —
                // and so a document the OFFICE keyed in on their behalf is
                // visible rather than looking like nothing happened.
                if (r.files.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  const SectionTitle('Already received'),
                  ...r.files.map((f) => _FileRow(file: f)),
                ],

                if (r.needsAction) ...[
                  const SizedBox(height: 14),
                  const SectionTitle('Add files'),
                  if (r.minFiles > 1) ...[
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        _shortBy == 0
                            ? 'This one needs ${r.minFiles} files — that is all of them.'
                            : 'This one needs ${r.minFiles} files in total. '
                                  '$_shortBy still to add.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          height: 1.35,
                          color: _shortBy == 0
                              ? AppColors.success
                              : theme.textTheme.bodySmall?.color,
                        ),
                      ),
                    ),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: _PickButton(
                          icon: Icons.photo_camera_rounded,
                          label: 'Camera',
                          onTap: _sending ? null : _addFromCamera,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _PickButton(
                          icon: Icons.photo_library_rounded,
                          label: 'Gallery',
                          onTap: _sending ? null : _addFromGallery,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _PickButton(
                          icon: Icons.description_rounded,
                          label: 'File',
                          onTap: _sending ? null : _addFile,
                        ),
                      ),
                    ],
                  ),
                  if (_picked.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    ..._picked.asMap().entries.map(
                      (e) => _PendingRow(
                        file: e.value,
                        onRemove: _sending
                            ? null
                            : () => setState(() => _picked.removeAt(e.key)),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    controller: _note,
                    enabled: !_sending,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Anything we should know (optional)',
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      _error!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.danger,
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  GradientButton(
                    label: _picked.isEmpty
                        ? 'Add a file to send'
                        : (_shortBy > 0
                              ? 'Add $_shortBy more'
                              : 'Send ${_picked.length} file${_picked.length == 1 ? '' : 's'}'),
                    icon: Icons.send_rounded,
                    loading: _sending,
                    onPressed: canSend ? _send : null,
                  ),
                ] else ...[
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Icon(
                        Icons.check_circle_rounded,
                        color: AppColors.success,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          r.awaitingReview
                              ? 'Sent. We will let you know if anything else is needed.'
                              : 'Received and accepted — nothing more to do.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PickButton extends StatelessWidget {
  const _PickButton({required this.icon, required this.label, this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          border: Border.all(color: theme.dividerColor),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Column(
          children: [
            Icon(icon, size: 21, color: AppColors.ember),
            const SizedBox(height: 5),
            Text(label, style: theme.textTheme.labelSmall),
          ],
        ),
      ),
    );
  }
}

class _PendingRow extends StatelessWidget {
  const _PendingRow({required this.file, this.onRemove});

  final PickedUpload file;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = file.name;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          const Icon(Icons.insert_drive_file_rounded, size: 17),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              name,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
          ),
          if (onRemove != null)
            IconButton(
              icon: const Icon(Icons.close_rounded, size: 17),
              onPressed: onRemove,
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
    );
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({required this.file});

  final RequestedFile file;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(
            file.fromCustomer
                ? Icons.mobile_friendly_rounded
                : Icons.support_agent_rounded,
            size: 17,
            color: AppColors.ember,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              file.name,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
          ),
          TextButton(
            onPressed: file.url.isEmpty ? null : () => _open(file.url),
            child: const Text('Open'),
          ),
        ],
      ),
    );
  }

  /// The portal returns a path relative to the API host — the same serve-file
  /// proxy the Documents tab opens.
  Future<void> _open(String path) async {
    final url = path.startsWith('http') ? path : '${Env.apiHost}$path';
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
