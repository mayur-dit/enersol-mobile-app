import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_client.dart';
import '../../core/data/customer_repository.dart';
import '../../core/models/customer_models.dart';
import '../../core/state/auth_service.dart';
import '../../core/state/screen_refresh.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/app_shell.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/page_scaffold.dart';
import '../../shared/widgets/segmented_tabs.dart';
import '../../shared/utils/focus_first_invalid.dart';
import '../../core/utils/errors.dart';
import '../../core/utils/date_format.dart';

/// Apply for a new installation, and track everything already applied for.
class ApplicationScreen extends StatefulWidget {
  const ApplicationScreen({super.key});

  @override
  State<ApplicationScreen> createState() => _ApplicationScreenState();
}

class _ApplicationScreenState extends State<ApplicationScreen>
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
            labels: const ['My Applications', 'New Application'],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _ApplicationStatusTab(onApply: () => _tabs.animateTo(1)),
              _NewApplicationTab(onSubmitted: () => _tabs.animateTo(0)),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Status tab ─────────────────────────────────────────────────────────────

class _ApplicationStatusTab extends StatefulWidget {
  const _ApplicationStatusTab({required this.onApply});

  /// Jumps to the New Application tab — the empty state's only useful action.
  final VoidCallback onApply;

  @override
  State<_ApplicationStatusTab> createState() => _ApplicationStatusTabState();
}

class _ApplicationStatusTabState extends State<_ApplicationStatusTab>
    with AutomaticKeepAliveClientMixin, ScreenRefresh {
  late Future<List<SolarApplication>> _future;

  @override
  bool get wantKeepAlive => true;

  /// Where a lead being confirmed, or a project moving a column, has to show up
  /// — and the screen a customer stares at while waiting for exactly that.
  @override
  int? get refreshTab => ShellTab.apply;

  @override
  void initState() {
    super.initState();
    _future = context.read<CustomerRepository>().applications();
  }

  @override
  Future<void> loadData() async {
    setState(() {
      _future = context.read<CustomerRepository>().applications();
    });
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return RefreshIndicator(
      onRefresh: refreshNow,
      color: AppColors.ember,
      child: FutureBuilder<List<SolarApplication>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.ember),
            );
          }
          if (snap.hasError) {
            return ErrorRetry(message: friendlyError(snap.error), onRetry: refreshNow);
          }

          final apps = snap.data ?? const <SolarApplication>[];
          if (apps.isEmpty) {
            return EmptyState(
              icon: Icons.description_outlined,
              title: 'No applications yet',
              subtitle:
                  'Apply for an installation and you can follow it here, step '
                  'by step.',
              // The empty state named a tab and left the customer to find it.
              action: SizedBox(
                width: 210,
                child: GradientButton(
                  label: 'Apply for solar',
                  icon: Icons.add_rounded,
                  height: 46,
                  onPressed: widget.onApply,
                ),
              ),
            );
          }

          return ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: tabInsets(context),
            itemCount: apps.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.lg),
            itemBuilder: (context, i) => _ApplicationCard(application: apps[i]),
          );
        },
      ),
    );
  }
}

class _ApplicationCard extends StatefulWidget {
  const _ApplicationCard({required this.application});

  final SolarApplication application;

  @override
  State<_ApplicationCard> createState() => _ApplicationCardState();
}

class _ApplicationCardState extends State<_ApplicationCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final app = widget.application;

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
                    Row(
                      children: [
                        Text(
                          app.reference,
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(width: 8),
                        // Tells apart an enquiry still in sales from a confirmed
                        // project, at a glance.
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: (app.isConfirmed
                                    ? AppColors.success
                                    : AppColors.info)
                                .withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                          ),
                          child: Text(
                            app.isConfirmed ? 'Project' : 'Enquiry',
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              color: app.isConfirmed
                                  ? AppColors.success
                                  : AppColors.info,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Applied ${fmtDate(app.submittedOn)}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              StatusChip(label: app.status, gradient: app.statusGradient),
            ],
          ),

          const SizedBox(height: 12),
          // Key facts as chips — capacity, type, board.
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (app.capacityKw > 0)
                _FactChip(
                  icon: Icons.solar_power_rounded,
                  label: '${app.capacityKw} kW',
                ),
              if (app.projectType != null)
                _FactChip(
                  icon: Icons.home_work_rounded,
                  label: app.projectType!,
                ),
              if (app.discom != null)
                _FactChip(
                  icon: Icons.electric_bolt_rounded,
                  label: app.discom!,
                ),
              if (app.expectedCompletion != null)
                _FactChip(
                  icon: Icons.event_available_rounded,
                  label:
                      'Est. ${fmtMonthYear(app.expectedCompletion)}',
                ),
            ],
          ),

          if (app.siteAddress != null) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.place_outlined,
                    size: 15, color: theme.textTheme.bodySmall?.color),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    app.siteAddress!,
                    style: theme.textTheme.bodySmall?.copyWith(height: 1.3),
                  ),
                ),
              ],
            ),
          ],

          // The headline the customer came for. Always drawn now — it falls
          // back to the server's own stage name, so a job whose timeline has no
          // step marked "current" (a brand-new enquiry, a finished project) no
          // longer shows a card that says nothing about where it is.
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              gradient: AppColors.brand,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Row(
              children: [
                const Icon(Icons.autorenew_rounded,
                    size: 15, color: Colors.white),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    'Now: ${app.currentLabel}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: LinearProgressIndicator(
              value: app.progress,
              minHeight: 7,
              backgroundColor:
                  theme.colorScheme.onSurface.withValues(alpha: 0.10),
              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.ember),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                '${app.completedCount} of ${app.stages.length} steps done',
                style: theme.textTheme.bodySmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              Text(
                _expanded ? 'Hide timeline' : 'View timeline',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.ember,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Icon(
                _expanded
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
                size: 19,
                color: AppColors.ember,
              ),
            ],
          ),

          AnimatedCrossFade(
            duration: const Duration(milliseconds: 220),
            crossFadeState: _expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: const SizedBox(width: double.infinity),
            secondChild: Padding(
              padding: const EdgeInsets.only(top: 16),
              child: _Timeline(stages: app.stages),
            ),
          ),
        ],
      ),
    );
  }
}

/// A small icon+label pill for a single application fact.
class _FactChip extends StatelessWidget {
  const _FactChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: theme.colorScheme.onSurface.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.10),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppColors.ember),
          const SizedBox(width: 5),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Vertical milestone list — the customer-facing view of the project pipeline.
///
/// The labels are the office's own board columns, sent down by the portal. A
/// confirmed job's timeline can run to a dozen steps across three phases, so the
/// phase name (`AppStage.group`) is printed the first time it changes: without
/// it the list reads as one long undifferentiated ladder in which "Design" and
/// "DISCOM approval" look like the same kind of thing.
class _Timeline extends StatelessWidget {
  const _Timeline({required this.stages});

  final List<AppStage> stages;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: List.generate(stages.length, (i) {
        final s = stages[i];
        final isLast = i == stages.length - 1;
        final startsPhase = s.group.isNotEmpty &&
            (i == 0 || stages[i - 1].group != s.group);

        final (Color dot, Color line) = switch (s.state) {
          StageState.done => (AppColors.success, AppColors.success),
          StageState.current => (AppColors.ember, AppColors.ember),
          StageState.pending => (
              theme.colorScheme.onSurface.withValues(alpha: 0.22),
              theme.colorScheme.onSurface.withValues(alpha: 0.14),
            ),
        };

        final row = IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                children: [
                  Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: s.state == StageState.pending
                          ? Colors.transparent
                          : dot,
                      shape: BoxShape.circle,
                      border: Border.all(color: dot, width: 2),
                    ),
                    child: s.state == StageState.done
                        ? const Icon(Icons.check,
                            size: 11, color: Colors.white)
                        : s.state == StageState.current
                            ? const Center(
                                child: SizedBox(
                                  width: 6,
                                  height: 6,
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ),
                              )
                            : null,
                  ),
                  if (!isLast)
                    Expanded(
                      child: Container(width: 2, color: line),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(bottom: isLast ? 0 : 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.label,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: s.state == StageState.current
                              ? FontWeight.w800
                              : FontWeight.w600,
                          color: s.state == StageState.pending
                              ? theme.textTheme.bodySmall?.color
                              : null,
                        ),
                      ),
                      if (s.date != null || s.note != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          [
                            if (s.date != null)
                              fmtDate(s.date),
                            if (s.note != null) s.note!,
                          ].join('  ·  '),
                          style: theme.textTheme.labelSmall?.copyWith(
                            height: 1.35,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        );

        if (!startsPhase) return row;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : AppSpacing.sm),
              child: Text(
                s.group.toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.9,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            row,
          ],
        );
      }),
    );
  }
}

// ── New application tab ────────────────────────────────────────────────────

class _NewApplicationTab extends StatefulWidget {
  const _NewApplicationTab({required this.onSubmitted});

  final VoidCallback onSubmitted;

  @override
  State<_NewApplicationTab> createState() => _NewApplicationTabState();
}

class _NewApplicationTabState extends State<_NewApplicationTab>
    with AutomaticKeepAliveClientMixin {
  final _formKey = GlobalKey<FormState>();

  final _name = TextEditingController();
  final _mobile = TextEditingController();
  final _address = TextEditingController();
  final _city = TextEditingController();
  final _pincode = TextEditingController();
  final _capacity = TextEditingController();
  final _notes = TextEditingController();

  // One per validated field, so a rejected submit can put the keyboard in the
  // first box that is actually holding it up rather than leaving the customer
  // to scroll for the red text.
  final _nameFocus = FocusNode();
  final _mobileFocus = FocusNode();
  final _addressFocus = FocusNode();
  final _cityFocus = FocusNode();
  final _pincodeFocus = FocusNode();
  final _capacityFocus = FocusNode();
  final _discomFocus = FocusNode();

  String _projectType = 'Residential';
  bool _busy = false;

  /// The electricity board. Required on a lead, so it is loaded from the
  /// discom master rather than typed.
  String? _discom;
  List<String> _discoms = const [];
  bool _discomsLoading = true;

  /// Exactly the values `elead_projectType_str` accepts — anything else is
  /// rejected by the schema's enum.
  static const _projectTypes = ['Residential', 'Commercial', 'Industrial'];

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    // Pre-fill from the signed-in profile — the customer should not retype
    // what we already hold.
    final user = context.read<AuthService>().user;
    _name.text = user?.name ?? '';
    _mobile.text = user?.mobile ?? '';
    _address.text = user?.address ?? '';
    _city.text = user?.city ?? '';
    _pincode.text = user?.pincode ?? '';
    _loadDiscoms();
  }

  Future<void> _loadDiscoms() async {
    try {
      final list = await context.read<CustomerRepository>().discoms();
      if (mounted) {
        setState(() {
          _discoms = list;
          _discomsLoading = false;
        });
      }
    } catch (_) {
      // Leave the picker empty rather than blocking the form; save still
      // insists on a value, so nothing invalid can be filed.
      if (mounted) setState(() => _discomsLoading = false);
    }
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _mobile,
      _address,
      _city,
      _pincode,
      _capacity,
      _notes,
    ]) {
      c.dispose();
    }
    for (final f in [
      _nameFocus,
      _mobileFocus,
      _addressFocus,
      _cityFocus,
      _pincodeFocus,
      _capacityFocus,
      _discomFocus,
    ]) {
      f.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) {
      // validate() paints the red text but leaves focus where it was, which on
      // a phone usually means the failing field is off screen entirely.
      focusFirstInvalid(_fields);
      return;
    }

    // Required on the lead, and a dropdown cannot be caught by a TextFormField
    // validator, so it is checked here.
    if (_discom == null || _discom!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select your electricity board.')),
      );
      // No controller — the picker's answer is `_discom`, which the validator
      // reads directly.
      focusFirstInvalid([
        FormFieldRef(focusNode: _discomFocus, validator: (_) => 'Required'),
      ]);
      return;
    }

    setState(() => _busy = true);
    try {
      final ref =
          await context.read<CustomerRepository>().submitApplication(
                name: _name.text.trim(),
                mobile: _mobile.text.trim(),
                address: _address.text.trim(),
                city: _city.text.trim(),
                pincode: _pincode.text.trim(),
                capacityKw: double.tryParse(_capacity.text.trim()) ?? 0,
                projectType: _projectType,
                discom: _discom!,
                notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
              );

      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.check_circle_rounded,
              color: AppColors.success, size: 44),
          title: const Text('Application submitted'),
          content: Text(
            'Your reference is $ref.\n\n'
            'Our team will call you to schedule a site survey.',
            textAlign: TextAlign.center,
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Done'),
            ),
          ],
        ),
      );

      if (!mounted) return;
      _formKey.currentState?.reset();
      _capacity.clear();
      _notes.clear();
      setState(() => _discom = null);
      widget.onSubmitted();
    } on ApiException catch (e) {
      // Surface what the server actually objected to — a silent generic
      // failure on a form this long is miserable to debug from the outside.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not submit. Please try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);

    return ListView(
      padding: tabInsets(context),
      children: [
        // Intro sits OUTSIDE any card — it is context for the whole form, not
        // content that belongs to its first section, and a form this long
        // reads as one undifferentiated block without something to set it
        // apart from the grouped cards below.
        Text(
          'Apply for a solar installation',
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        Text(
          'Tell us about your site. Our engineer will survey the roof and '
          'share a proposal.',
          style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
        ),
        const SizedBox(height: 6),
        // A LEGEND, said once, rather than "(optional)" repeated in every
        // label that doesn't need an asterisk — seven fields with roughly the
        // same disclaimer is noise, one line at the top is not.
        Row(
          children: [
            Text(
              '*',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: AppColors.danger, fontWeight: FontWeight.w800),
            ),
            const SizedBox(width: 4),
            Text('Required', style: theme.textTheme.labelSmall),
          ],
        ),
        const SizedBox(height: 18),

        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Your details ──────────────────────────────────────────
              const SectionTitle('Your details'),
              GlassCard(
                child: Column(
                  children: [
                    _Field(
                      controller: _name,
                      focusNode: _nameFocus,
                      label: 'Full name *',
                      icon: Icons.person_outline,
                      validator: _required,
                    ),
                    _Field(
                      controller: _mobile,
                      focusNode: _mobileFocus,
                      label: 'Mobile number *',
                      icon: Icons.phone_outlined,
                      keyboardType: TextInputType.phone,
                      maxLength: 10,
                      last: true,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      validator: _validateMobile,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // ── Site details ──────────────────────────────────────────
              const SectionTitle('Site details'),
              GlassCard(
                child: Column(
                  children: [
                    _Field(
                      controller: _address,
                      focusNode: _addressFocus,
                      label: 'Site address *',
                      icon: Icons.home_outlined,
                      maxLines: 2,
                      validator: _required,
                    ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _Field(
                            controller: _city,
                            focusNode: _cityFocus,
                            label: 'City *',
                            icon: Icons.location_city_outlined,
                            validator: _required,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _Field(
                            controller: _pincode,
                            focusNode: _pincodeFocus,
                            label: 'Pincode *',
                            icon: Icons.markunread_mailbox_outlined,
                            keyboardType: TextInputType.number,
                            maxLength: 6,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            validator: _validatePincode,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      initialValue: _projectType,
                      decoration: const InputDecoration(
                        labelText: 'Property type',
                        prefixIcon: Icon(Icons.apartment_outlined),
                      ),
                      items: _projectTypes
                          .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                          .toList(),
                      onChanged: (v) =>
                          setState(() => _projectType = v ?? 'Residential'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // ── System requirements ───────────────────────────────────
              const SectionTitle('System requirements'),
              GlassCard(
                child: Column(
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: _discom,
                      focusNode: _discomFocus,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: 'Electricity board *',
                        prefixIcon: const Icon(Icons.electric_bolt_outlined),
                        helperText: _discomsLoading
                            ? 'Loading…'
                            : (_discoms.isEmpty
                                ? 'Could not load the list — pull down to retry'
                                : null),
                      ),
                      items: _discoms
                          .map((d) => DropdownMenuItem(
                                value: d,
                                child: Text(d, overflow: TextOverflow.ellipsis),
                              ))
                          .toList(),
                      onChanged: _discoms.isEmpty
                          ? null
                          : (v) => setState(() => _discom = v),
                    ),
                    const SizedBox(height: 14),
                    _Field(
                      controller: _capacity,
                      focusNode: _capacityFocus,
                      label: 'Required capacity (kW)',
                      icon: Icons.solar_power_outlined,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      helperText: 'Not sure? Leave blank — we will advise.',
                      last: true,
                      validator: _validateCapacity,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // ── Notes ─────────────────────────────────────────────────
              const SectionTitle('Anything else?'),
              GlassCard(
                child: _Field(
                  controller: _notes,
                  label: 'Notes (optional)',
                  icon: Icons.notes_outlined,
                  maxLines: 3,
                  last: true,
                ),
              ),
              const SizedBox(height: 22),

              GradientButton(
                label: 'Submit application',
                icon: Icons.send_rounded,
                loading: _busy,
                onPressed: _busy ? null : _submit,
              ),
            ],
          ),
        ),
      ],
    );
  }

  String? _required(String? v) =>
      (v == null || v.trim().isEmpty) ? 'This field is required' : null;

  // Named rather than inline on the field, so `_submit` can re-run the very
  // same check to find which box to jump to. An inline copy would be a second
  // definition of "valid" that drifts from the one the field enforces.
  String? _validateMobile(String? v) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return 'Enter your mobile number';
    if (!RegExp(r'^[6-9]\d{9}$').hasMatch(t)) {
      return 'Enter a valid 10-digit mobile number';
    }
    return null;
  }

  String? _validatePincode(String? v) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return 'Required';
    if (t.length != 6) return '6 digits';
    return null;
  }

  String? _validateCapacity(String? v) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return null;
    final n = double.tryParse(t);
    if (n == null || n <= 0) return 'Enter a valid number';
    if (n > 1000) return 'That looks too large';
    return null;
  }

  /// Every validated box, in the order the form lays them out.
  List<FormFieldRef> get _fields => [
        FormFieldRef(focusNode: _nameFocus, validator: _required, controller: _name),
        FormFieldRef(focusNode: _mobileFocus, validator: _validateMobile, controller: _mobile),
        FormFieldRef(focusNode: _addressFocus, validator: _required, controller: _address),
        FormFieldRef(focusNode: _cityFocus, validator: _required, controller: _city),
        FormFieldRef(focusNode: _pincodeFocus, validator: _validatePincode, controller: _pincode),
        FormFieldRef(focusNode: _capacityFocus, validator: _validateCapacity, controller: _capacity),
      ];
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    required this.icon,
    this.focusNode,
    this.validator,
    this.keyboardType,
    this.maxLines = 1,
    this.maxLength,
    this.inputFormatters,
    this.helperText,
    this.last = false,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final FocusNode? focusNode;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final int maxLines;
  final int? maxLength;
  final List<TextInputFormatter>? inputFormatters;
  final String? helperText;

  /// The last field in its card — drops the bottom gap that every OTHER field
  /// needs to clear the one below it. Without this every card carried an
  /// extra 14px of dead space under its final field, on top of the card's own
  /// padding, so a short card (a single field) read as oddly tall.
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 14),
      child: TextFormField(
        controller: controller,
        focusNode: focusNode,
        validator: validator,
        keyboardType: keyboardType,
        maxLines: maxLines,
        maxLength: maxLength,
        inputFormatters: inputFormatters,
        decoration: InputDecoration(
          labelText: label,
          helperText: helperText,
          counterText: '',
          prefixIcon: Icon(icon),
        ),
      ),
    );
  }
}
