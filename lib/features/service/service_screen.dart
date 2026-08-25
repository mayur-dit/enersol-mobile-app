import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/data/customer_repository.dart';
import '../../core/models/customer_models.dart';
import '../../core/state/screen_refresh.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/utils/focus_first_invalid.dart';
import '../../shared/widgets/app_shell.dart';
import '../../shared/widgets/confirm_dialog.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/page_scaffold.dart';
import '../../core/utils/errors.dart';
import '../../core/utils/date_format.dart';

/// Operation & Maintenance: raise a request, follow its log.
class ServiceScreen extends StatefulWidget {
  const ServiceScreen({super.key});

  @override
  State<ServiceScreen> createState() => _ServiceScreenState();
}

class _ServiceScreenState extends State<ServiceScreen> with ScreenRefresh {
  late Future<List<ServiceRequest>> _future;

  /// A request the customer is waiting on is the one thing here that changes
  /// without them touching it — and the desk's reply arrives as a notification.
  @override
  int? get refreshTab => ShellTab.service;

  @override
  void initState() {
    super.initState();
    _future = context.read<CustomerRepository>().serviceRequests();
  }

  @override
  Future<void> loadData() async {
    setState(() {
      _future = context.read<CustomerRepository>().serviceRequests();
    });
    await _future;
  }

  Future<void> _raise() async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _RaiseRequestSheet(),
    );
    if (created == true) refreshNow();
  }

  /// Whether the floating "New request" button is on screen.
  ///
  /// ONE CALL TO ACTION AT A TIME. The empty state already offers the only
  /// thing there is to do here, and the FAB used to float over it — two buttons,
  /// two different labels ("Raise a request" / "New request"), two shapes, for
  /// one action. It also sat over the spinner and over the error panel, offering
  /// to file a request against a list that had failed to load.
  bool _showFab = false;

  @override
  Widget build(BuildContext context) {
    final navClearance = shellBottomInset(context, extra: 0);

    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: refreshNow,
          color: AppColors.ember,
          child: FutureBuilder<List<ServiceRequest>>(
            future: _future,
            builder: (context, snap) {
              final items = snap.data ?? const <ServiceRequest>[];
              final wantFab =
                  snap.connectionState != ConnectionState.waiting &&
                  !snap.hasError &&
                  items.isNotEmpty;
              // Deferred: this runs during build, and the FAB is a sibling in
              // the same Stack.
              if (wantFab != _showFab) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) setState(() => _showFab = wantFab);
                });
              }

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

              if (items.isEmpty) {
                return EmptyState(
                  icon: Icons.build_outlined,
                  title: 'No service requests yet',
                  subtitle:
                      'Raise a request and our service desk will pick it up.',
                  action: SizedBox(
                    width: 210,
                    child: GradientButton(
                      label: 'Raise a request',
                      icon: Icons.add_rounded,
                      height: 46,
                      onPressed: _raise,
                    ),
                  ),
                );
              }

              final open = items.where((r) => r.isOpen).toList();
              final closed = items.where((r) => !r.isOpen).toList();

              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                // Enough room for the nav bar and the floating button above it,
                // so the last card is never trapped behind either.
                padding: tabInsets(context, extra: 84),
                children: [
                  if (open.isNotEmpty) ...[
                    const SectionTitle('Open requests'),
                    ...open.map(
                      (r) => Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.gap),
                        child: _RequestCard(request: r),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                  if (closed.isNotEmpty) ...[
                    const SectionTitle('History'),
                    ...closed.map(
                      (r) => Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.gap),
                        child: _RequestCard(request: r),
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
        if (_showFab)
          Positioned(
            right: AppSpacing.lg,
            bottom: navClearance + AppSpacing.lg,
            child: FloatingActionButton.extended(
              onPressed: _raise,
              backgroundColor: AppColors.ember,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_rounded),
              label: const Text('New request'),
            ),
          ),
      ],
    );
  }
}

class _RequestCard extends StatefulWidget {
  const _RequestCard({required this.request});

  final ServiceRequest request;

  @override
  State<_RequestCard> createState() => _RequestCardState();
}

class _RequestCardState extends State<_RequestCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = widget.request;

    return GlassCard(
      onTap: () => setState(() => _expanded = !_expanded),
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
                      r.type,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${r.reference}  ·  '
                      '${fmtDate(r.raisedOn)}',
                      style: theme.textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
              StatusChip(label: r.status, gradient: r.statusGradient),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            r.description,
            maxLines: _expanded ? null : 2,
            overflow: _expanded ? null : TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
          ),
          if (r.logs.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(
                  Icons.forum_outlined,
                  size: 14,
                  color: theme.textTheme.labelSmall?.color,
                ),
                const SizedBox(width: 5),
                Text(
                  '${r.logs.length} update${r.logs.length == 1 ? '' : 's'}',
                  style: theme.textTheme.labelSmall,
                ),
                const Spacer(),
                Text(
                  _expanded ? 'Hide log' : 'View log',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppColors.ember,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Icon(
                  _expanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: 18,
                  color: AppColors.ember,
                ),
              ],
            ),
            AnimatedCrossFade(
              duration: const Duration(milliseconds: 200),
              crossFadeState: _expanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              firstChild: const SizedBox(width: double.infinity),
              secondChild: Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Column(
                  children: r.logs
                      .map(
                        (l) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                margin: const EdgeInsets.only(top: 5),
                                width: 7,
                                height: 7,
                                decoration: const BoxDecoration(
                                  color: AppColors.ember,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${l.by}  ·  '
                                      '${fmtDateTime(l.at)}',
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      l.note,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(height: 1.35),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Bottom sheet for raising a new request.
class _RaiseRequestSheet extends StatefulWidget {
  const _RaiseRequestSheet();

  @override
  State<_RaiseRequestSheet> createState() => _RaiseRequestSheetState();
}

class _RaiseRequestSheetState extends State<_RaiseRequestSheet> {
  final _formKey = GlobalKey<FormState>();
  final _description = TextEditingController();
  final _descriptionFocus = FocusNode();

  String? _validateDescription(String? v) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return 'Please describe the problem';
    if (t.length < 10) return 'Add a little more detail';
    return null;
  }

  String _type = kServiceTypes.first;
  bool _busy = false;

  @override
  void dispose() {
    _description.dispose();
    _descriptionFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      focusFirstInvalid([
        FormFieldRef(
          focusNode: _descriptionFocus,
          validator: _validateDescription,
          controller: _description,
        ),
      ]);
      return;
    }

    setState(() => _busy = true);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    try {
      final ref = await context.read<CustomerRepository>().raiseServiceRequest(
        type: _type,
        description: _description.text.trim(),
      );
      // Only if the sheet is STILL THERE. Dragged away mid-send it is not, and
      // this pop would have closed the screen underneath it instead.
      if (mounted) navigator.pop(true);
      messenger.showSnackBar(SnackBar(content: Text('Request $ref created.')));
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        // The server's own sentence, which is written for customers, rather
        // than a blanket failure — see friendlyError.
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              friendlyError(
                e,
                fallback:
                    'Could not send the request. Check your connection and '
                    'try again.',
              ),
            ),
          ),
        );
      }
    }
  }

  /// Back out of the sheet, but not out of a half-written request.
  ///
  /// The sheet is the only place the description exists, so dismissing it
  /// throws the text away — worth one question. A send already under way is not
  /// interruptible at all: the request is with the server either way, and
  /// closing early leaves the list behind showing nothing was raised.
  Future<void> _back() async {
    final navigator = Navigator.of(context);

    if (_busy) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sending your request — one moment.')),
      );
      return;
    }

    if (_description.text.trim().isEmpty) {
      navigator.pop();
      return;
    }

    final discard = await confirmAction(
      context,
      icon: Icons.delete_outline_rounded,
      title: 'Discard this request?',
      message: 'What you have typed will not be saved.',
      cancelLabel: 'Keep editing',
      confirmLabel: 'Discard',
      confirmColor: AppColors.danger,
    );
    if (discard) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Back decides for itself what to do — see [_back]. `canPop: false` also
    // takes the barrier tap through the same question.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkChrome : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: SafeArea(
            top: false,
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.18,
                        ),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Raise a service request',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  // Said up front rather than discovered by being refused. A
                  // customer whose job is not commissioned yet can still ask us
                  // something, and until now pressing Send told them only that
                  // the server had failed.
                  if (context
                          .read<CustomerRepository>()
                          .hasCommissionedProject ==
                      false) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Your installation is not commissioned yet, so this will be '
                      'logged against your application and answered by our team.',
                      style: theme.textTheme.labelSmall?.copyWith(height: 1.4),
                    ),
                  ],
                  const SizedBox(height: 18),

                  // Chips rather than a dropdown: six fixed types are all
                  // visible and one tap apart, so opening an overlay to pick
                  // one only added a step. A dropdown is the right control for
                  // a list that grows (the electricity-board picker on Apply is
                  // exactly that); this one never does.
                  Text('Type of issue', style: theme.textTheme.labelSmall),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: kServiceTypes.map((t) {
                      final selected = _type == t;
                      return ChoiceChip(
                        label: Text(t),
                        selected: selected,
                        onSelected: (_) => setState(() => _type = t),
                        showCheckmark: false,
                        selectedColor: AppColors.ember.withValues(alpha: 0.16),
                        side: BorderSide(
                          color: selected
                              ? AppColors.ember
                              : theme.dividerColor,
                        ),
                        labelStyle: theme.textTheme.bodySmall?.copyWith(
                          color: selected ? AppColors.ember : null,
                          fontWeight: selected
                              ? FontWeight.w800
                              : FontWeight.w500,
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 18),

                  TextFormField(
                    controller: _description,
                    focusNode: _descriptionFocus,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Describe the problem',
                      alignLabelWithHint: true,
                    ),
                    validator: _validateDescription,
                  ),
                  const SizedBox(height: 20),

                  GradientButton(
                    label: 'Submit request',
                    icon: Icons.send_rounded,
                    loading: _busy,
                    onPressed: _busy ? null : _submit,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
