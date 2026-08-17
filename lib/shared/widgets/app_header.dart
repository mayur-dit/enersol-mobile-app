import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import 'app_logo.dart';

/// The app bar used on every screen: back on the left, logo centred, alerts and
/// menu on the right.
///
/// CENTRED AGAINST THE HEADER, NOT AGAINST WHAT IS LEFT OVER. The logo sits in a
/// [Stack] rather than in a `Row`'s `Expanded`, because the two sides are not
/// the same width: back is one 48px slot, the trailing side is the bell (44) and
/// the menu (48) together. Centring inside the residual space put the logo 22px
/// left of the screen's middle on every shell tab — visible against the footer's
/// own centred items, and the reason this file used to claim an optical centring
/// it did not have.
///
/// The back and menu slots each keep their width whether or not they hold a
/// button, so the logo does not shift as you move between a root tab and a
/// pushed screen.
///
/// ALERTS ARE A BELL, NOT A TAB. They are something that comes to you rather
/// than somewhere you go, and the five footer slots are all destinations. The
/// bell carries the unread count, so "is there anything new?" is answered
/// without a tap from wherever the customer already is.
class AppHeader extends StatelessWidget implements PreferredSizeWidget {
  const AppHeader({
    super.key,
    this.onMenuTap,
    this.onAlertsTap,
    this.unread = 0,
    this.showBack,
    this.onBack,
    this.title,
  });

  /// Opens the sidebar. When null the menu button is hidden — used by screens
  /// pushed on top of the shell, which own no drawer.
  final VoidCallback? onMenuTap;

  /// Opens the alerts inbox. Null on the inbox itself and on screens pushed
  /// over the shell, where the bell would point at where you already are.
  final VoidCallback? onAlertsTap;

  /// Unread alerts, for the badge. Zero draws no badge.
  final int unread;

  /// Defaults to "whenever this route can be popped".
  final bool? showBack;

  /// What the back arrow does. Defaults to popping the route; the shell passes
  /// its own handler so a tab with nothing to pop still lands on Home rather
  /// than doing nothing.
  final VoidCallback? onBack;

  /// Optional caption shown under the logo, naming the current screen.
  final String? title;

  @override
  Size get preferredSize => Size.fromHeight(title == null ? 60 : 74);

  @override
  Widget build(BuildContext context) {
    final canPop = showBack ?? Navigator.of(context).canPop();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SafeArea(
      bottom: false,
      child: Container(
        height: preferredSize.height,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isDark ? AppColors.darkHairline : AppColors.lightHairline,
            ),
          ),
        ),
        child: Stack(
          children: [
            // The logo fills the bar and centres in it, so where it lands does
            // not depend on how many buttons happen to be on either side.
            Positioned.fill(
              child: IgnorePointer(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const AppLogo(height: 26),
                      if (title != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          title!,
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    letterSpacing: 0.6,
                                    fontWeight: FontWeight.w600,
                                  ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            // The buttons sit over it, pinned to their own edges.
            Row(
              children: [
                SizedBox(
                  width: 48,
                  child: canPop
                      ? IconButton(
                          icon: const Icon(Icons.arrow_back_ios_new, size: 19),
                          tooltip: 'Back',
                          onPressed:
                              onBack ?? () => Navigator.of(context).maybePop(),
                        )
                      : null,
                ),
                const Spacer(),
                if (onAlertsTap != null)
                  SizedBox(
                    width: 48,
                    child: _BellButton(unread: unread, onTap: onAlertsTap!),
                  ),
                SizedBox(
                  width: 48,
                  child: onMenuTap == null
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.menu, size: 23),
                          tooltip: 'Menu',
                          onPressed: onMenuTap,
                        ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The bell, with its count sitting ON the icon.
///
/// The number goes on the glyph rather than beside it because the header is the
/// narrowest row in the app: a badge that took its own horizontal space would
/// make the trailing side jump every time the count crossed 9 or 99.
class _BellButton extends StatelessWidget {
  const _BellButton({required this.unread, required this.onTap});

  final int unread;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: unread > 0 ? '$unread unread alerts' : 'Alerts',
      onPressed: onTap,
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          const Icon(Icons.notifications_none_rounded, size: 23),
          if (unread > 0)
            Positioned(
              right: -5,
              top: -4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                constraints: const BoxConstraints(minWidth: 15),
                decoration: BoxDecoration(
                  color: AppColors.ember,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Text(
                  unread > 99 ? '99+' : '$unread',
                  textAlign: TextAlign.center,
                  // Never scaled: this badge is sized to the icon it sits on,
                  // and the Settings font slider would otherwise push it off
                  // the glyph entirely at the largest step.
                  textScaler: TextScaler.noScaling,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9.5,
                    height: 1.2,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
