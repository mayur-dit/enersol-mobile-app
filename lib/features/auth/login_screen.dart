import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_client.dart';
import '../../core/config/env.dart';
import '../../core/state/auth_service.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/utils/focus_first_invalid.dart';
import '../../shared/widgets/app_backdrop.dart';
import '../../shared/widgets/app_logo.dart';
import '../../shared/widgets/confirm_dialog.dart';
import '../../shared/widgets/glass_card.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  // So a rejected sign-in puts the cursor back in the empty box.
  final _userFocus = FocusNode();
  final _passFocus = FocusNode();

  String? _requiredUser(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Enter your username' : null;
  String? _requiredPass(String? v) =>
      (v == null || v.isEmpty) ? 'Enter your password' : null;

  bool _obscure = true;
  bool _busy = false;
  String? _error;

  /// Shown only when the device has biometrics AND the user armed them.
  bool _bioReady = false;
  BiometricKind _bioKind = BiometricKind.none;
  String _version = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();
    _checkBiometric();
  }

  @override
  void dispose() {
    _userCtrl.dispose();
    _passCtrl.dispose();
    _userFocus.dispose();
    _passFocus.dispose();
    super.dispose();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() => _version = 'v${info.version} (${info.buildNumber})');
      }
    } catch (_) {
      // Version is decorative; a failure here must not block sign-in.
    }
  }

  Future<void> _checkBiometric() async {
    final auth = context.read<AuthService>();
    final available = await auth.biometricAvailable();
    final enrolled = await auth.biometricEnrolled();
    final kind = await auth.biometricKind();
    if (mounted) {
      setState(() {
        _bioReady = available && enrolled;
        _bioKind = kind;
      });
    }
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) {
      focusFirstInvalid([
        FormFieldRef(
          focusNode: _userFocus,
          validator: _requiredUser,
          controller: _userCtrl,
        ),
        FormFieldRef(
          focusNode: _passFocus,
          validator: _requiredPass,
          controller: _passCtrl,
        ),
      ]);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await context.read<AuthService>().login(_userCtrl.text, _passCtrl.text);
      // On success the root swaps in the shell; nothing to do here.
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e, stack) {
      // Everything the transport can fail at is already turned into an
      // ApiException by ApiClient._send, so reaching here means the failure was
      // on the DEVICE (secure storage, a plugin channel) — the one class of
      // login failure the screen alone can tell us nothing about. Log it, or a
      // tester on a physical phone has only "Something went wrong" to report.
      debugPrint('Login failed (${e.runtimeType}): $e\n$stack');
      if (mounted) setState(() => _error = 'Something went wrong. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _biometricLogin() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<AuthService>().loginWithBiometric();
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _error = e.message);
        _checkBiometric();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// True while the exit question is on screen, so a second back press does not
  /// stack a second copy of it behind the first.
  bool _asking = false;

  /// Back on the login screen is back on the FIRST screen — there is nothing
  /// behind it, so the press either closes the app or does nothing. It asks,
  /// the same as Home does.
  Future<void> _back() async {
    if (_asking) return;
    _asking = true;
    try {
      await confirmExit(context);
    } finally {
      if (mounted) _asking = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        resizeToAvoidBottomInset: true,
        body: AppBackdrop(
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 28, 22, 22),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const AppLogo(height: 54),
                      const SizedBox(height: 10),
                      Text(
                        'Customer Portal',
                        style: theme.textTheme.titleSmall?.copyWith(
                          letterSpacing: 1.4,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 26),

                      GlassCard(
                        strong: true,
                        padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'Sign in',
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Track your solar application, documents and generation.',
                                style: theme.textTheme.bodySmall,
                              ),
                              const SizedBox(height: 22),

                              TextFormField(
                                controller: _userCtrl,
                                focusNode: _userFocus,
                                textInputAction: TextInputAction.next,
                                autocorrect: false,
                                enableSuggestions: false,
                                decoration: const InputDecoration(
                                  labelText: 'Username',
                                  hintText: 'Your Enersol username',
                                  prefixIcon: Icon(Icons.person_outline),
                                ),
                                validator: _requiredUser,
                              ),
                              const SizedBox(height: 14),

                              TextFormField(
                                controller: _passCtrl,
                                focusNode: _passFocus,
                                obscureText: _obscure,
                                textInputAction: TextInputAction.done,
                                onFieldSubmitted: (_) => _submit(),
                                decoration: InputDecoration(
                                  labelText: 'Password',
                                  prefixIcon: const Icon(Icons.lock_outline),
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _obscure
                                          ? Icons.visibility_off_outlined
                                          : Icons.visibility_outlined,
                                      size: 20,
                                    ),
                                    onPressed: () =>
                                        setState(() => _obscure = !_obscure),
                                  ),
                                ),
                                validator: _requiredPass,
                              ),

                              if (_error != null) ...[
                                const SizedBox(height: 16),
                                _ErrorBanner(message: _error!),
                              ],

                              const SizedBox(height: 22),
                              GradientButton(
                                label: 'Sign In',
                                icon: Icons.login_rounded,
                                loading: _busy,
                                onPressed: _busy ? null : _submit,
                              ),

                              if (_bioReady) ...[
                                const SizedBox(height: 16),
                                Row(
                                  children: [
                                    const Expanded(child: Divider()),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                      ),
                                      child: Text(
                                        'or',
                                        style: theme.textTheme.bodySmall,
                                      ),
                                    ),
                                    const Expanded(child: Divider()),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                OutlinedButton.icon(
                                  onPressed: _busy ? null : _biometricLogin,
                                  icon: Icon(
                                    _bioKind == BiometricKind.face
                                        ? Icons.face_rounded
                                        : Icons.fingerprint,
                                    size: 24,
                                  ),
                                  label: Text('Sign in with ${_bioKind.label}'),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 24),
                      if (_version.isNotEmpty)
                        Text(_version, style: theme.textTheme.labelSmall),
                      const SizedBox(height: 6),
                      Text(
                        'Developed by ${Env.developerName}',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
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

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, color: AppColors.danger, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.danger,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
