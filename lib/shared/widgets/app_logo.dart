import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// The Enersol wordmark, picking the artwork that suits the current scheme.
///
/// Two files ship because the wordmark's text flips colour between schemes;
/// the bulb glyph alone is scheme-agnostic and used where space is tight.
class AppLogo extends StatelessWidget {
  const AppLogo({
    super.key,
    this.height = 30,
    this.bulbOnly = false,
    this.wordmarkOnly = false,
  });

  final double height;

  /// Just the bulb, no lettering.
  final bool bulbOnly;

  /// The lettering WITHOUT the "Life. Empowered." strapline underneath.
  ///
  /// The strapline is set very small relative to the wordmark: at the ~24px the
  /// header can spare it renders about four pixels tall, which is a grey smudge
  /// rather than a readable line — and it sat directly above the screen name,
  /// so the header carried three stacked text rows of which only two could be
  /// read. Cropping it is the header's business only; every other placement
  /// (login, splash, drawer footer) has the room and shows the full lock-up.
  final bool wordmarkOnly;

  /// Where the wordmark ends and the strapline begins, as fractions of the
  /// artwork's full height.
  ///
  /// MEASURED, NOT GUESSED — rendering `enersol-logo-dark-bg.svg` and scanning
  /// it for rows containing ink gives three bands: the lettering and bulb at
  /// 0.151–0.699, the two marks under the bulb at 0.715–0.811, and the
  /// strapline at 0.872–1.000. The window below keeps the first two with a
  /// little air and drops the third. Re-measure if the artwork is ever redrawn.
  static const double _cropTop = 0.115;
  static const double _cropBottom = 0.850;

  @override
  Widget build(BuildContext context) {
    if (bulbOnly) {
      return SvgPicture.asset(
        'assets/logo/enersol-bulb.svg',
        height: height,
        semanticsLabel: 'Enersol',
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final asset = isDark
        ? 'assets/logo/enersol-logo-dark-bg.svg'
        : 'assets/logo/enersol-logo-white-bg.svg';

    if (!wordmarkOnly) {
      return SvgPicture.asset(asset, height: height, semanticsLabel: 'Enersol');
    }

    // Draw the artwork oversized, then show only the slice that holds the
    // lettering. `heightFactor` shrinks the box to that slice; the alignment
    // slides the artwork inside it so the slice — not the artwork's own middle
    // — is what the box frames.
    const window = _cropBottom - _cropTop;
    const centre = (_cropTop + _cropBottom) / 2;
    return ClipRect(
      child: Align(
        alignment: Alignment(0, 2 * (window / 2 - centre) / (window - 1) - 1),
        heightFactor: window,
        child: SvgPicture.asset(
          asset,
          height: height / window,
          semanticsLabel: 'Enersol',
        ),
      ),
    );
  }
}
