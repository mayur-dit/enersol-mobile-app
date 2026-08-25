import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import 'app_logo.dart';

/// The app bar used on EVERY screen: back on the left, logo centred, alerts and
/// menu on the right, and the screen's name on its own line underneath.
///
/// TWO ROWS, NOT ONE STACK. The brand row is a fixed height that the logo and
/// all three buttons share, and the caption sits in a second row below it. That
/// separation is the whole point: while the buttons and the logo+caption were
/// stacked as one block, the buttons — 48px of [IconButton] in a [Stack] that
/// aligns to `topStart` by default — were pinned to the TOP of a 74px bar,
/// riding 13px above its middle with dead space beneath them, and the caption
/// had to be squeezed into whatever the logo left over. Now each row centres its
/// own contents and neither can push the other around.
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
    this.title,
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

  /// Caption naming the current screen, shown under the logo.
  final String? title;

  /// The line the logo and the buttons share. 48 is the tap target every
  /// [IconButton] wants; the extra 4 keeps the glyphs off the hairline.
  static const double _brandRow = 52;

  /// Nominal height of the caption line, for [preferredSize] only — the row
  /// itself is sized by its text, so the Settings font slider can grow it.
  static const double _captionRow = 18;

  /// Air between the caption and the hairline, so the name is not sitting on it.
  static const double _bottomPad = 6;

  /// One button's worth of width. Held even when the button is absent.
  static const double _slot = 48;

  @override
  Size get preferredSize => Size.fromHeight(
    title == null
        ? _brandRow + _bottomPad
        : _brandRow + _captionRow + _bottomPad,
  );

  @override
  Widget build(BuildContext context) {
    final canPop = showBack ?? Navigator.of(context).canPop();
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return SafeArea(
      bottom: false,
      child: Container(
        // NO FIXED HEIGHT. [preferredSize] is the nominal figure; the bar
        // itself is sized by its rows, so raising the Settings font slider
        // makes the caption taller instead of clipping it against a hard 74.
        // Symmetric left/right, so the centre of this box IS the centre of the
        // screen and the logo lands on it.
        padding: EdgeInsets.fromLTRB(4, 0, 4, title == null ? 0 : _bottomPad),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isDark ? AppColors.darkHairline : AppColors.lightHairline,
            ),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: _brandRow,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Dead centre of the full width, and vertically centred on
                  // the same line the buttons occupy.
                  const IgnorePointer(
                    child: AppLogo(height: 24, wordmarkOnly: true),
                  ),
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
                              : _BellButton(
                                  unread: unread,
                                  onTap: onAlertsTap!,
                                ),
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
            if (title != null)
              // Its own row, clear of the buttons, so it can use the full width
              // and only has to stay off the screen edges.
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  title!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelMedium?.copyWith(
                    letterSpacing: 1.1,
                    height: 1.15,
                    fontWeight: FontWeight.w700,
                    color: isDark ? AppColors.darkText2 : AppColors.lightText2,
                  ),
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
