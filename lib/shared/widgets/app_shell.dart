import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/data/customer_repository.dart';
import '../../core/state/notification_service.dart';
import '../../core/state/screen_refresh.dart';
import '../../core/theme/app_theme.dart';
import '../../features/application/application_screen.dart';
import '../../features/documents/documents_screen.dart';
import '../../features/generation/generation_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/notifications/notifications_screen.dart';
import '../../features/service/service_screen.dart';
import 'app_backdrop.dart';
import 'app_drawer.dart';
import 'app_header.dart';

/// Footer destinations, in the order they appear.
///
/// Named rather than bare indices because Home, the drawer and the quick-action
/// tiles all navigate by position — a reorder would silently send them to the
/// wrong screen otherwise.
class ShellTab {
  const ShellTab._();
  static const home = 0;
  static const apply = 1;
  static const power = 2;
  static const docs = 3;
  static const service = 4;
}

/// The signed-in frame: header on top, five destinations along the bottom.
///
/// Tabs live in an [IndexedStack] so each keeps its scroll offset and any
/// in-flight form state when the user moves between them.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  final _drawerKey = GlobalKey<ScaffoldState>();

  /// Home is the landing tab.
  ///
  /// Generation used to be, back when it served an invented "representative
  /// week" that always had something on it. It reads real meter entries now, so
  /// for every customer whose system is not yet commissioned — which is every
  /// customer the app is most useful to — opening on it meant opening on an
  /// empty screen. Home summarises whatever the customer actually has.
  int _index = ShellTab.home;

  /// The same number, shared DOWN the tree so each tab can tell whether it is
  /// the one on screen — see [VisibleTab]. A notifier rather than a rebuild of
  /// the whole stack: switching tabs must not rebuild five screens.
  final ValueNotifier<int> _visible = ValueNotifier<int>(ShellTab.home);

  StreamSubscription<String>? _routeSub;

  static const _titles = [
    'HOME',
    'APPLICATION',
    'GENERATION',
    'DOCUMENTS',
    'SERVICE',
  ];

  /// Where a tapped push lands. The backend writes the WEB app's paths, so the
  /// ones this app can honour are mapped onto its tabs and the rest are left as
  /// read-only news in the inbox — the same table NotificationsScreen uses.
  static const _routeToTab = {
    '/service': ShellTab.service,
    '/documents': ShellTab.docs,
    // Where a "your application has moved on" push lands.
    '/application': ShellTab.apply,
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // The shell exists only when there is a session, which makes it the right
    // and only place to bring notifications up. Deferred one frame so the first
    // build is not competing with a socket handshake and an FCM registration.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final service = context.read<NotificationService>();
      _routeSub = service.routes.listen(_openRoute);
      unawaited(service.start());
    });
  }

  @override
  void dispose() {
    _routeSub?.cancel();
    _visible.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Coming back to the app is the moment everything on screen is most likely to
  /// be stale: the socket dies while backgrounded, and a push the user swiped
  /// away is a notification nothing else will tell us about. `start()` is
  /// idempotent — it re-reads and reconnects rather than starting a second of
  /// anything — and `invalidate()` tells the tabs the same thing about the data
  /// they are still showing from before the phone was pocketed.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !mounted) return;
    unawaited(context.read<NotificationService>().start());
    context.read<CustomerRepository>().invalidate();
  }

  void _openRoute(String url) {
    final tab = _routeToTab[url.split('?').first];
    if (tab != null) _select(tab);
  }

  void _select(int i) {
    setState(() => _index = i);
    _visible.value = i;
  }

  Future<void> _openAlerts() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NotificationsScreen(onOpenTab: _select),
      ),
    );
  }

  /// Back leaves the current tab for Home. On Home itself the arrow is hidden,
  /// so this never becomes a no-op button.
  void _back() {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
      return;
    }
    _select(ShellTab.home);
  }

  @override
  Widget build(BuildContext context) {
    final onHome = _index == ShellTab.home;
    final unread = context.watch<NotificationService>().unread;

    // Android back should walk to Home before leaving the app.
    return PopScope(
      canPop: onHome,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _select(ShellTab.home);
      },
      child: Scaffold(
        key: _drawerKey,
        extendBody: true,
        backgroundColor: Colors.transparent,
        drawer: AppDrawer(currentTab: _index, onSelectTab: _select),
        body: AppBackdrop(
          child: Column(
            children: [
              AppHeader(
                title: _titles[_index],
                showBack: !onHome,
                onBack: _back,
                unread: unread,
                onAlertsTap: _openAlerts,
                onMenuTap: () => _drawerKey.currentState?.openDrawer(),
              ),
              Expanded(
                // Every tab below stays mounted, so each needs to know whether
                // it is the one being read before it re-reads anything.
                child: VisibleTab(
                  index: _visible,
                  child: IndexedStack(
                    index: _index,
                    children: [
                      HomeScreen(onNavigate: _select),
                      const ApplicationScreen(),
                      const GenerationScreen(),
                      const DocumentsScreen(),
                      const ServiceScreen(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: _FooterNav(index: _index, onSelect: _select),
      ),
    );
  }
}

class _FooterNav extends StatelessWidget {
  const _FooterNav({required this.index, required this.onSelect});

  final int index;
  final ValueChanged<int> onSelect;

  static const _items = [
    (icon: Icons.home_outlined, active: Icons.home_rounded, label: 'Home'),
    (
      icon: Icons.description_outlined,
      active: Icons.description_rounded,
      label: 'Apply'
    ),
    (icon: Icons.bolt_outlined, active: Icons.bolt_rounded, label: 'Power'),
    (icon: Icons.folder_outlined, active: Icons.folder_rounded, label: 'Docs'),
    (icon: Icons.build_outlined, active: Icons.build_rounded, label: 'Service'),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.darkChrome.withValues(alpha: 0.97)
            : Colors.white.withValues(alpha: 0.97),
        border: Border(
          top: BorderSide(
            color: isDark ? AppColors.darkHairline : AppColors.lightHairline,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.34 : 0.07),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 62,
          child: Row(
            children: List.generate(_items.length, (i) {
              final item = _items[i];
              final selected = i == index;

              return Expanded(
                child: InkWell(
                  onTap: () => onSelect(i),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // The active pill reads as the brand gradient; inactive
                      // icons stay muted so the current tab is unmistakable.
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOutCubic,
                        padding: EdgeInsets.symmetric(
                          horizontal: selected ? 16 : 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          gradient: selected ? AppColors.brand : null,
                          borderRadius:
                              BorderRadius.circular(AppRadius.pill),
                        ),
                        child: Icon(
                          selected ? item.active : item.icon,
                          size: 21,
                          color: selected
                              ? Colors.white
                              : (isDark
                                  ? AppColors.darkText3
                                  : AppColors.lightText3),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        item.label,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w500,
                          color: selected
                              ? AppColors.ember
                              : (isDark
                                  ? AppColors.darkText3
                                  : AppColors.lightText3),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}
