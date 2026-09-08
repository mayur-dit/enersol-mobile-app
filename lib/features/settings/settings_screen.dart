import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../../core/config/env.dart';
import '../../core/state/auth_service.dart';
import '../../core/state/notification_service.dart';
import '../../core/state/settings_service.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/page_scaffold.dart';

/// Appearance, text size and fingerprint sign-in.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _bioAvailable = false;
  bool _bioEnabled = false;
  bool _bioBusy = false;
  BiometricKind _bioKind = BiometricKind.none;
  String _version = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final auth = context.read<AuthService>();
    final available = await auth.biometricAvailable();
    final enabled = await auth.biometricEnrolled();
    final kind = await auth.biometricKind();

    String version = '';
    try {
      final info = await PackageInfo.fromPlatform();
      version = 'Version ${info.version} (${info.buildNumber})';
    } catch (_) {
      // Non-critical.
    }

    if (mounted) {
      setState(() {
        _bioAvailable = available;
        _bioEnabled = enabled;
        _bioKind = kind;
        _version = version;
      });
    }
  }

  /// No password prompt: AuthService now seals the SESSION already open in
  /// this screen behind the fingerprint, rather than the password, so there is
  /// nothing left here to re-verify. The biometric prompt itself is the only
  /// confirmation needed.
  Future<void> _toggleBiometric(bool on) async {
    final auth = context.read<AuthService>();
    final messenger = ScaffoldMessenger.of(context);

    if (!on) {
      await auth.disableBiometric();
      if (mounted) setState(() => _bioEnabled = false);
      return;
    }

    setState(() => _bioBusy = true);
    final ok = await auth.enableBiometric();
    if (!mounted) return;
    setState(() {
      _bioEnabled = ok;
      _bioBusy = false;
    });
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          ok ? 'Fingerprint sign-in enabled.' : 'Fingerprint was not confirmed.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final theme = Theme.of(context);

    return PageScaffold(
      title: 'Settings',
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: pageInsets(context),
        children: [
          // ── Appearance ────────────────────────────────────────────────
          const SectionTitle('Appearance'),
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Theme',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _ThemeOption(
                      icon: Icons.light_mode_rounded,
                      label: 'Light',
                      selected: settings.themeMode == ThemeMode.light,
                      onTap: () => settings.setThemeMode(ThemeMode.light),
                    ),
                    const SizedBox(width: 10),
                    _ThemeOption(
                      icon: Icons.dark_mode_rounded,
                      label: 'Dark',
                      selected: settings.themeMode == ThemeMode.dark,
                      onTap: () => settings.setThemeMode(ThemeMode.dark),
                    ),
                    const SizedBox(width: 10),
                    _ThemeOption(
                      icon: Icons.brightness_auto_rounded,
                      label: 'System',
                      selected: settings.themeMode == ThemeMode.system,
                      onTap: () => settings.setThemeMode(ThemeMode.system),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // ── Text size ─────────────────────────────────────────────────
          const SectionTitle('Text size'),
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Font size',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    Text(
                      settings.fontSize.label,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.ember,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Slider(
                  value: AppFontSize.values.indexOf(settings.fontSize)
                      .toDouble(),
                  min: 0,
                  max: (AppFontSize.values.length - 1).toDouble(),
                  divisions: AppFontSize.values.length - 1,
                  activeColor: AppColors.ember,
                  label: settings.fontSize.label,
                  onChanged: (v) =>
                      settings.setFontSize(AppFontSize.values[v.round()]),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 4, right: 4, top: 4),
                  child: Text(
                    'The quick brown fox jumps over the lazy dog.',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // ── Security ──────────────────────────────────────────────────
          const SectionTitle('Security'),
          GlassCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _bioEnabled,
              onChanged:
                  (!_bioAvailable || _bioBusy) ? null : _toggleBiometric,
              secondary: Icon(
                _bioKind == BiometricKind.face
                    ? Icons.face_rounded
                    : Icons.fingerprint,
                size: 26,
              ),
              title: Text(
                '${_bioKind == BiometricKind.none ? 'Biometric' : _bioKind.label} sign-in',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                _bioAvailable
                    ? 'Sign in with ${_bioKind.label} instead of typing your '
                        'password.'
                    : 'No biometric is enrolled on this device.',
                style: theme.textTheme.labelSmall?.copyWith(height: 1.35),
              ),
            ),
          ),

          const SizedBox(height: 20),

          // ── Notifications ─────────────────────────────────────────────
          const SectionTitle('Notifications'),
          const _NotificationsCard(),

          const SizedBox(height: 26),

          // ── About ─────────────────────────────────────────────────────
          Center(
            child: Column(
              children: [
                if (_version.isNotEmpty)
                  Text(_version, style: theme.textTheme.labelSmall),
                const SizedBox(height: 4),
                Text(
                  'Developed by ${Env.developerName}',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Whether alerts can actually reach this phone, and a way to try again.
///
/// NOT a toggle. Push permission belongs to the OS — a switch here would
/// pretend to own something it cannot change, and the honest version of that
/// control is a link into the system settings, which Android and iOS both
/// already put one tap from the app icon. What this app CAN usefully say is
/// which of the two delivery paths is working, because "I never got told" is
/// the actual complaint and until now nothing on any screen could answer it.
class _NotificationsCard extends StatefulWidget {
  const _NotificationsCard();

  @override
  State<_NotificationsCard> createState() => _NotificationsCardState();
}

class _NotificationsCardState extends State<_NotificationsCard> {
  bool _busy = false;
  bool _testing = false;

  /// The outcome of the last test alert, kept on screen.
  ///
  /// A SnackBar was the obvious place for this and the wrong one: the answer to
  /// "did it arrive?" has to still be readable while the customer is pulling
  /// down their notification shade to look.
  String? _testResult;

  /// Re-run the WHOLE setup, push half included.
  ///
  /// This used to call `start()`, which by this point in the app's life takes
  /// its idempotent early return and only re-reads the inbox and re-opens the
  /// socket — it never re-requests the OS permission or re-fetches a token. So
  /// a customer who did exactly what the text above told them to do, granted
  /// notifications in system settings and came back to press the button, was
  /// told nothing had changed. It had.
  Future<void> _retry() async {
    final service = context.read<NotificationService>();
    setState(() {
      _busy = true;
      _testResult = null;
    });
    await service.recheckDelivery();
    if (mounted) setState(() => _busy = false);
  }

  /// Send a real alert to this phone and say what happened.
  ///
  /// The card above can only report what the app believes about its own
  /// plumbing; this is the only control that proves it, because it goes all the
  /// way out to Firebase and back through the OS like every real notification.
  Future<void> _test() async {
    final service = context.read<NotificationService>();
    setState(() {
      _testing = true;
      _testResult = null;
    });
    final result = await service.sendTestAlert();
    if (mounted) {
      setState(() {
        _testing = false;
        _testResult = result;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = context.watch<NotificationService>();

    // The socket's state changes without going through notifyListeners — it is
    // a ValueListenable of its own — so a plain watch() would leave this card
    // reading "not getting through" for as long as the user stared at it after
    // the connection came back.
    return ValueListenableBuilder(
      valueListenable: service.connection,
      builder: (context, _, _) => _body(context, service),
    );
  }

  Widget _body(BuildContext context, NotificationService service) {
    final theme = Theme.of(context);

    final pushOk = service.pushWorking;
    final socketOk = service.socketLive;
    final healthy = pushOk || socketOk;

    // A build with no Firebase app registered can never get a push token, so
    // saying "allow notifications in your phone settings" would send the
    // customer to fix something that is not broken on their side.
    final unbuilt = service.pushSetupNote.isNotEmpty;

    final detail = !service.pushSupported
        ? 'This device cannot receive push notifications.'
        : unbuilt
            ? 'Alerts show while the app is open. Alerts with the app closed '
                'are not switched on in this version of the app yet.'
        : pushOk && socketOk
            ? 'Alerts reach you whether the app is open or closed.'
            : pushOk
                ? 'Alerts will reach you when the app is closed. The live '
                    'connection is down — it comes back on its own.'
                : socketOk
                    ? 'Alerts show while the app is open. To be told when it '
                        'is closed, allow notifications for Enersol in your '
                        'phone settings.'
                    : 'Nothing can reach this phone right now. Check your '
                        'connection, and that notifications are allowed for '
                        'Enersol in your phone settings.';

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                healthy
                    ? Icons.notifications_active_rounded
                    : Icons.notifications_off_rounded,
                size: 24,
                color: healthy ? AppColors.success : AppColors.warning,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  healthy ? 'Alerts are on' : 'Alerts are not getting through',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            detail,
            style: theme.textTheme.labelSmall?.copyWith(height: 1.4),
          ),
          if (service.pushSupported) ...[
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                OutlinedButton.icon(
                  onPressed: _busy || _testing ? null : _retry,
                  icon: _busy
                      ? const SizedBox(
                          width: 15,
                          height: 15,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_rounded, size: 18),
                  label: Text(_busy ? 'Checking…' : 'Check again'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy || _testing ? null : _test,
                  icon: _testing
                      ? const SizedBox(
                          width: 15,
                          height: 15,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_rounded, size: 18),
                  label: Text(_testing ? 'Sending…' : 'Send a test alert'),
                ),
              ],
            ),
            if (_testResult != null) ...[
              const SizedBox(height: AppSpacing.md),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm + 2,
                ),
                decoration: BoxDecoration(
                  color: AppColors.info.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Text(
                  _testResult!,
                  style: theme.textTheme.labelSmall?.copyWith(height: 1.4),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _ThemeOption extends StatelessWidget {
  const _ThemeOption({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            gradient: selected ? AppColors.brand : null,
            color: selected
                ? null
                : theme.colorScheme.onSurface.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(
              color: selected
                  ? Colors.transparent
                  : theme.colorScheme.onSurface.withValues(alpha: 0.12),
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                size: 21,
                color: selected ? Colors.white : theme.textTheme.bodySmall?.color,
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color:
                      selected ? Colors.white : theme.textTheme.bodySmall?.color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

