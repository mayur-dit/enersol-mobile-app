import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/state/auth_service.dart';
import '../../core/state/notification_service.dart';
import '../../core/theme/app_theme.dart';
import '../../features/documents/document_requests_screen.dart';
import '../../features/notifications/notifications_screen.dart';
import '../../features/profile/profile_screen.dart';
import '../../features/referral/referral_screen.dart';
import '../../features/settings/settings_screen.dart';
import 'app_logo.dart';
import 'confirm_dialog.dart';
import 'app_shell.dart';

/// The sidebar opened from the header's menu button.
///
/// It repeats the five footer destinations (so the drawer is a complete map of
/// the app, not a leftovers bin) and adds the screens that have no tab.
class AppDrawer extends StatelessWidget {
  const AppDrawer({
    super.key,
    required this.currentTab,
    required this.onSelectTab,
  });

  /// Index of the active footer tab, highlighted in the list.
  final int currentTab;

  /// Switches the shell to a footer tab.
  final ValueChanged<int> onSelectTab;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final user = auth.user;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Drawer(
      backgroundColor: isDark
          ? AppColors.darkChrome
          : Colors.white.withValues(alpha: 0.98),
      child: SafeArea(
        child: Column(
          children: [
            // ── Identity ──────────────────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(18, 20, 18, 20),
              decoration: const BoxDecoration(gradient: AppColors.brand),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: Colors.white.withValues(alpha: 0.22),
                        child: Text(
                          user?.initials ?? '?',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 17,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              user?.name ?? 'Guest',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 15.5,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              user?.email ?? user?.userName ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.9),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // ── Destinations ──────────────────────────────────────────────
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  // Same order as the footer, so the two never disagree.
                  _tile(context, Icons.home_rounded, 'Home', ShellTab.home),
                  _tile(
                    context,
                    Icons.description_rounded,
                    'Application',
                    ShellTab.apply,
                  ),
                  _tile(
                    context,
                    Icons.bolt_rounded,
                    'Generation',
                    ShellTab.power,
                  ),
                  _tile(
                    context,
                    Icons.folder_rounded,
                    'Documents',
                    ShellTab.docs,
                  ),
                  _tile(
                    context,
                    Icons.build_rounded,
                    'Service (O&M)',
                    ShellTab.service,
                  ),
                  const Divider(height: 18, indent: 16, endIndent: 16),
                  // Listed even though the header's bell goes to the same
                  // screen: the bell is a glyph with a number on it, and this
                  // drawer is meant to be a complete map of the app.
                  _push(
                    context,
                    Icons.notifications_rounded,
                    'Alerts',
                    NotificationsScreen(onOpenTab: onSelectTab),
                    badge: context.watch<NotificationService>().unread,
                  ),
                  // The ONLY way back to an outstanding request once the
                  // notification that announced it has been swiped away.
                  // Before this it was reachable from the alert and from Home ->
                  // project card -> progress, which is three taps and a guess
                  // for the customer the office is actively chasing.
                  _push(
                    context,
                    Icons.upload_file_rounded,
                    'Documents needed',
                    const DocumentRequestsScreen(),
                  ),
                  _push(
                    context,
                    Icons.card_giftcard_rounded,
                    'Refer & Earn',
                    const ReferralScreen(),
                  ),
                  _push(
                    context,
                    Icons.person_rounded,
                    'Profile',
                    const ProfileScreen(),
                  ),
                  _push(
                    context,
                    Icons.settings_rounded,
                    'Settings',
                    const SettingsScreen(),
                  ),
                ],
              ),
            ),

            const Divider(height: 1),
            ListTile(
              leading: const Icon(
                Icons.logout_rounded,
                color: AppColors.danger,
                size: 21,
              ),
              title: Text(
                'Sign out',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppColors.danger,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onTap: () => _confirmLogout(context),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const AppLogo(height: 16, bulbOnly: true),
                  const SizedBox(width: 8),
                  Text('Enersol Customer', style: theme.textTheme.labelSmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tile(BuildContext context, IconData icon, String label, int index) {
    final selected = currentTab == index;
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: ListTile(
        dense: true,
        selected: selected,
        selectedTileColor: AppColors.ember.withValues(alpha: 0.12),
        leading: Icon(icon, size: 21, color: selected ? AppColors.ember : null),
        title: Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? AppColors.ember : null,
          ),
        ),
        onTap: () {
          // Just the drawer: [onSelectTab] does its own unwinding when this
          // drawer belongs to a pushed screen rather than to the shell.
          Navigator.of(context).pop();
          onSelectTab(index);
        },
      ),
    );
  }

  Widget _push(
    BuildContext context,
    IconData icon,
    String label,
    Widget screen, {

    /// A count to show on the right of the row. Zero draws nothing.
    int badge = 0,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: ListTile(
        dense: true,
        leading: Icon(icon, size: 21),
        title: Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
        ),
        trailing: badge <= 0
            ? null
            : Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.ember,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Text(
                  badge > 99 ? '99+' : '$badge',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
        onTap: () {
          final navigator = Navigator.of(context);
          // Close the drawer, then unwind to the shell BEFORE pushing. The
          // drawer now hangs off every pushed screen as well as the shell, so
          // without this Settings -> menu -> Profile -> menu -> Settings would
          // stack routes without limit and the back arrow would walk the whole
          // chain. One pushed screen at a time, always over the tabs.
          navigator.pop();
          navigator.popUntil((r) => r.isFirst);
          navigator.push(MaterialPageRoute<void>(builder: (_) => screen));
        },
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final navigator = Navigator.of(context);
    final auth = context.read<AuthService>();

    final ok = await confirmAction(
      context,
      icon: Icons.logout_rounded,
      title: 'Sign out?',
      message: 'You will need to sign in again to continue.',
      confirmLabel: 'Sign out',
      confirmColor: AppColors.danger,
    );

    if (ok) {
      await auth.logout();
      // The root listens to auth state and swaps in the login screen, so just
      // unwind whatever is stacked above it.
      navigator.popUntil((r) => r.isFirst);
    }
  }
}
