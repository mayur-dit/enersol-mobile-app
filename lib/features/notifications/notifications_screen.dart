import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_client.dart';
import '../../core/models/notification.dart';
import '../../core/utils/errors.dart';
import '../../core/state/notification_service.dart';
import '../../core/theme/app_theme.dart';
import '../documents/document_requests_screen.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/app_shell.dart';
import '../../shared/widgets/page_scaffold.dart';

/// The customer's alerts: service updates, released documents, application
/// progress.
///
/// Pushed on top of the shell rather than given a tab. A tab is for something
/// you go to; alerts are something that comes to you, so the way in is the bell
/// in the header — which also carries the unread badge, so the count is visible
/// without spending a slot in a five-item footer that is already full.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key, this.onOpenTab});

  /// Lets a tapped alert land on the tab it is about. Null when there is no
  /// shell underneath to switch (the screen is still readable).
  final ValueChanged<int>? onOpenTab;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    // Opening the screen is the cheapest moment to reconcile with the server —
    // a push may have arrived while the socket was down.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<NotificationService>().refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final service = context.watch<NotificationService>();
    final items = service.items;

    return PageScaffold(
      title: 'Alerts',
      // The only screen that drops the bell — it would point at itself. The
      // menu stays, so the header still matches every other screen.
      showAlerts: false,
      child: RefreshIndicator(
        onRefresh: service.refresh,
        child: Builder(
          builder: (context) {
            if (service.loading && items.isEmpty) {
              return const Center(child: CircularProgressIndicator());
            }
            if (service.error != null && items.isEmpty) {
              return ErrorRetry(
                message: friendlyError(ApiException(service.error!)),
                onRetry: service.refresh,
              );
            }
            if (items.isEmpty) {
              // EmptyState is pullable in its own right now — wrapping it in a
              // second ListView here would nest two scrollables.
              return const EmptyState(
                icon: Icons.notifications_none_rounded,
                title: 'Nothing new yet',
                subtitle:
                    'Updates about your application, service requests and '
                    'documents will appear here.',
              );
            }

            return ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              // A pushed route, so there is no footer nav to clear — only the
              // device's own gesture inset.
              padding: pageInsets(context),
              itemCount: items.length + 1,
              separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
              itemBuilder: (context, i) {
                if (i == 0) return _Header(unread: service.unread);
                final n = items[i - 1];
                return _NotificationTile(
                  notification: n,
                  onTap: () => _open(service, n),
                );
              },
            );
          },
        ),
      ),
    );
  }

  /// Open what an alert is about.
  ///
  /// The routes the backend writes are the ENGINEER/web app's paths, so this
  /// maps the ones this app can honour onto its own tabs and treats the rest as
  /// read-only news. Mapping here rather than asking the backend for a third
  /// link keeps one field meaning "the mobile destination" across both mobile
  /// clients.
  void _open(NotificationService service, AppNotification n) {
    if (!n.isRead) service.markRead(n.id);

    // Document requests are a PUSHED screen, not a tab: the whole point of the
    // notification is to land on the upload for one particular request, and a
    // tab cannot carry which one. The link is `/document-requests/<id>`.
    if (n.link.startsWith('/document-requests')) {
      service.markEntityRead(n.entity, n.entityId);
      final id = n.link.split('/').where((p) => p.isNotEmpty).skip(1).firstOrNull;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => DocumentRequestsScreen(highlightId: id),
        ),
      );
      return;
    }

    final tab = switch (n.link) {
      '/service' => ShellTab.service,
      '/documents' => ShellTab.docs,
      '/application' => ShellTab.apply,
      _ => null,
    };
    if (tab == null) return;

    // Everything about this record is now old news.
    service.markEntityRead(n.entity, n.entityId);
    widget.onOpenTab?.call(tab);
    Navigator.of(context).maybePop();
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.unread});

  final int unread;

  @override
  Widget build(BuildContext context) {
    final service = context.read<NotificationService>();
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              unread == 0 ? 'All caught up' : '$unread unread',
              style: Theme.of(context)
                  .textTheme
                  .labelLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          if (unread > 0)
            TextButton(
              onPressed: service.markAllRead,
              child: const Text('Mark all read'),
            ),
        ],
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.notification, required this.onTap});

  final AppNotification notification;
  final VoidCallback onTap;

  /// Icon and tint per type. The backend also writes a Font Awesome class and a
  /// colour on every row, but those are web classes — a native app cannot
  /// render them, so the mapping is repeated here in Material's vocabulary.
  (IconData, Color) get _look => switch (notification.type) {
        'SERVICE_UPDATED' => (Icons.support_agent_rounded, AppColors.info),
        'SERVICE_ASSIGNED' => (Icons.handyman_rounded, AppColors.ember),
        'DOCUMENT_PUBLISHED' => (Icons.description_rounded, AppColors.success),
        'PROJECT_ASSIGNED' => (Icons.solar_power_rounded, AppColors.info),
        'APPLICATION_PROGRESS' => (Icons.route_rounded, AppColors.ember),
        _ => (Icons.notifications_rounded, AppColors.ember),
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, tint) = _look;
    final unread = !notification.isRead;

    return GlassCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: tint.withValues(alpha: 0.12),
            ),
            child: Icon(icon, size: 19, color: tint),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        notification.title,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight:
                              unread ? FontWeight.w700 : FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      notification.age,
                      style: theme.textTheme.labelSmall,
                    ),
                  ],
                ),
                if (notification.body.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    notification.body,
                    style: theme.textTheme.bodySmall?.copyWith(height: 1.35),
                  ),
                ],
              ],
            ),
          ),
          if (unread) ...[
            const SizedBox(width: 8),
            Container(
              margin: const EdgeInsets.only(top: 6),
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.ember,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
