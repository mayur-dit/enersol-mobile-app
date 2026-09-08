import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import 'app_logo.dart';

/// The app bar used on EVERY screen: back on the left, logo centred, alerts and
/// menu on the right. ONE ROW, AND ONLY THE BRAND.
///
/// THE SCREEN'S NAME IS NOT IN HERE. It used to sit on a second line under the
/// logo — a small centred all-caps caption — and it read as an afterthought
/// hung off the bottom of the brand bar rather than as the page's own heading:
/// 16 logical pixels of gap above it, 7 below it, and the whole thing pinned
/// under artwork it had nothing to do with. It now belongs to the page, drawn
/// by [PageTitle] as the first line of the content, where a heading goes. The
/// header is the brand and the three controls, nothing else.
///
/// CENTRED AGAINST THE HEADER, NOT AGAINST WHAT IS LEFT OVER. The logo is a
/// [Stack] child rather than a `Row`'s `Expanded`, because the two sides are not
/// the same width: back is one slot, the trailing side is the bell and the menu
/// together. Centring inside the residual space put the logo 22px left of the
/// screen's middle — visible against the footer's own centred items.
///
/// The back and menu slots each keep their width whether or not they hold a
/// button, so nothing shifts as you move between a root tab and a pushed screen.
///
/// ALERTS ARE A BELL, NOT A TAB. They are something that comes to you rather
/// than somewhere you go, and the five footer slots are all destinations. The
/// bell carries the unread count, so "is there anything new?" is answered
/// without a tap from wherever the customer already is. It is hidden on exactly
/// one screen — the alerts list itself, where it would point at where you are.
class AppHeader extends StatelessWidget implements PreferredSizeWidget {
  const AppHeader({
    super.key,
    this.onMenuTap,
    this.onAlertsTap,
    this.unread = 0,
    this.showBack,
    this.onBack,
  });

  /// Opens the sidebar.
  final VoidCallback? onMenuTap;

  /// Opens the alerts inbox. Null only on the inbox itself.
  final VoidCallback? onAlertsTap;

  /// Unread alerts, for the badge. Zero draws no badge.
  final int unread;

  /// Defaults to "whenever this route can be popped".
  final bool? showBack;

  /// What the back arrow does. Defaults to popping the route; the shell passes
  /// its own handler so a tab with nothing to pop still lands on Home rather
  /// than doing nothing.
  final VoidCallback? onBack;

  /// The line the logo and the buttons share. 48 is the tap target every
  /// [IconButton] wants; the extra 4 keeps the glyphs off the hairline.
  static const double _brandRow = 52;

  /// One button's worth of width. Held even when the button is absent.
  static const double _slot = 48;

  @override
  Size get preferredSize => const Size.fromHeight(_brandRow);

  @override
  Widget build(BuildContext context) {
    final canPop = showBack ?? Navigator.of(context).canPop();
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return SafeArea(
      bottom: false,
      child: Container(
        height: _brandRow,
        // Symmetric left/right, so the centre of this box IS the centre of the
        // screen and the logo lands on it.
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isDark ? AppColors.darkHairline : AppColors.lightHairline,
            ),
          ),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Dead centre of the full width, and vertically centred on the
            // same line the buttons occupy.
            const IgnorePointer(child: AppLogo(height: 24, wordmarkOnly: true)),
            Positioned.fill(
              child: Row(
                children: [
                  SizedBox(
                    width: _slot,
                    child: canPop
                        ? IconButton(
                            icon: const Icon(
                              Icons.arrow_back_ios_new,
                              size: 19,
                            ),
                            tooltip: 'Back',
                            onPressed:
                                onBack ??
                                () => Navigator.of(context).maybePop(),
                          )
                        : null,
                  ),
                  const Spacer(),
                  SizedBox(
                    width: _slot,
                    child: onAlertsTap == null
                        ? null
                        : _BellButton(unread: unread, onTap: onAlertsTap!),
                  ),
                  SizedBox(
                    width: _slot,
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
