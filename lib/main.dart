import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'core/api/api_client.dart';
import 'core/data/customer_repository.dart';
import 'core/state/auth_service.dart';
import 'core/state/notification_service.dart';
import 'core/state/settings_service.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/login_screen.dart';
import 'shared/widgets/app_backdrop.dart';
import 'shared/widgets/app_logo.dart';
import 'shared/widgets/app_shell.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  runApp(const EnersolApp());
}

/// Owns the long-lived services.
///
/// Stateful so the client, session and repository survive rebuilds — building
/// them inside `build` would hand every screen a fresh, empty session each time
/// the theme changed.
class EnersolApp extends StatefulWidget {
  const EnersolApp({super.key});

  @override
  State<EnersolApp> createState() => _EnersolAppState();
}

class _EnersolAppState extends State<EnersolApp> {
  late final ApiClient _api;
  late final AuthService _auth;
  late final SettingsService _settings;
  late final CustomerRepository _repo;
  late final NotificationService _notifications;

  @override
  void initState() {
    super.initState();
    _api = ApiClient();
    _auth = AuthService(_api)..restore();
    _settings = SettingsService()..load();
    // Every query is scoped to the signed-in customer, so the repository needs
    // the session rather than just the transport.
    _repo = CustomerRepository(_api, _auth);
    // Built here rather than inside the shell so it OUTLIVES the shell: the
    // socket and the FCM registration must survive a sign-out and the login
    // screen that replaces it, and the service listens to the session itself to
    // tear itself down. It is not started here — AppShell does that, once
    // there is a session to start it with.
    // A notification is the office telling us it just changed something — so it
    // also invalidates whatever the mounted screens are still showing. Without
    // this the app announced a new document and then showed "No documents yet"
    // on the tab the notification pointed at, until it was killed and reopened.
    _notifications = NotificationService(_api, _auth, onNews: _repo.invalidate);
  }

  @override
  void dispose() {
    _notifications.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<ApiClient>.value(value: _api),
        Provider<CustomerRepository>.value(value: _repo),
        ChangeNotifierProvider<AuthService>.value(value: _auth),
        ChangeNotifierProvider<SettingsService>.value(value: _settings),
        ChangeNotifierProvider<NotificationService>.value(value: _notifications),
      ],
      child: Consumer<SettingsService>(
        builder: (context, settings, _) {
          return MaterialApp(
            title: 'Enersol',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: settings.themeMode,
            // One multiplier drives every screen, so the Settings slider
            // scales the whole app rather than each widget guessing.
            builder: (context, child) {
              final media = MediaQuery.of(context);
              return MediaQuery(
                data: media.copyWith(
                  textScaler: TextScaler.linear(settings.fontSize.scale),
                ),
                child: child ?? const SizedBox.shrink(),
              );
            },
            home: const _AuthGate(),
          );
        },
      ),
    );
  }
}

/// Chooses between the splash, the login screen and the signed-in shell.
class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();

    if (auth.restoring) return const _Splash();

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      child: auth.isAuthenticated
          ? const AppShell(key: ValueKey('shell'))
          : const LoginScreen(key: ValueKey('login')),
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.transparent,
      body: AppBackdrop(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppLogo(height: 58),
              SizedBox(height: 26),
              SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: AppColors.ember,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
