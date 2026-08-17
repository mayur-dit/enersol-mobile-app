import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import 'app_backdrop.dart';
import 'app_header.dart';

/// Frame for a screen pushed on top of the shell (Profile, Settings, Referral).
///
/// Carries the same header as the tabs — back on the left, logo centred — but
/// no menu button, since a pushed route has no drawer of its own.
class PageScaffold extends StatelessWidget {
  const PageScaffold({
    super.key,
    required this.title,
    required this.child,
    this.floatingActionButton,
  });

  final String title;
  final Widget child;
  final Widget? floatingActionButton;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: floatingActionButton,
      body: AppBackdrop(
        child: Column(
          children: [
            AppHeader(title: title, showBack: true),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

/// Bottom inset that clears the shell's footer nav.
///
/// The shell sets `extendBody`, so every tab paints *behind* the 62-high nav
/// bar and whatever gesture inset the device adds. Scroll padding and floating
/// buttons must both allow for it, or the last row ends up unreachable.
double shellBottomInset(BuildContext context, {double extra = 16}) =>
    62 + MediaQuery.viewPaddingOf(context).bottom + extra;

/// Scroll padding for a screen INSIDE the shell — clears the footer nav.
EdgeInsets tabInsets(BuildContext context, {double extra = 24}) =>
    EdgeInsets.fromLTRB(
      AppSpacing.page,
      AppSpacing.md,
      AppSpacing.page,
      shellBottomInset(context, extra: extra),
    );

/// Scroll padding for a screen PUSHED OVER the shell — no nav bar, but the
/// device's own gesture inset is still there.
///
/// The pushed routes each carried a hard-coded `30` before this, which is
/// neither the tabs' padding nor an allowance for the home indicator, so the
/// last row on Settings sat under the gesture bar on a modern iPhone.
EdgeInsets pageInsets(BuildContext context, {double extra = 24}) => EdgeInsets.fromLTRB(
      AppSpacing.page,
      AppSpacing.md,
      AppSpacing.page,
      MediaQuery.viewPaddingOf(context).bottom + extra,
    );

/// Section heading used down the long scrolling screens.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 6, 2, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text.toUpperCase(),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.9,
                  ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Makes a centred panel pullable inside a [RefreshIndicator].
///
/// An `overflow`-free `Center` is not a scroll container, so a RefreshIndicator
/// wrapped around one has nothing to listen to and the gesture is silently
/// dead — which is exactly what happened on six screens, all of them the screens
/// where a customer most wants to pull: the ones showing nothing. A
/// `ListView` with `AlwaysScrollableScrollPhysics` gives the gesture something
/// to grab while still centring its single child.
class _Pullable extends StatelessWidget {
  const _Pullable({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(minHeight: box.maxHeight),
            child: Center(child: child),
          ),
        ],
      ),
    );
  }
}

/// Shown when a screen's data load actually failed, with the reason and a
/// retry — far more useful than an empty state that looks like "no data".
class ErrorRetry extends StatelessWidget {
  const ErrorRetry({super.key, required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _Pullable(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 74,
              height: 74,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.danger.withValues(alpha: 0.10),
              ),
              child: const Icon(Icons.cloud_off_rounded,
                  size: 33, color: AppColors.danger),
            ),
            const SizedBox(height: 16),
            Text(
              "Couldn't load",
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _Pullable(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 74,
              height: 74,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.ember.withValues(alpha: 0.10),
              ),
              child: Icon(icon, size: 33, color: AppColors.ember),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
              ),
            ],
            if (action != null) ...[const SizedBox(height: 20), action!],
          ],
        ),
      ),
    );
  }
}
