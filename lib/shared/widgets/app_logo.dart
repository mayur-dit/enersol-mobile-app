import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// The Enersol wordmark, picking the artwork that suits the current scheme.
///
/// Two files ship because the wordmark's text flips colour between schemes;
/// the bulb glyph alone is scheme-agnostic and used where space is tight.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.height = 30, this.bulbOnly = false});

  final double height;
  final bool bulbOnly;

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
    return SvgPicture.asset(
      isDark
          ? 'assets/logo/enersol-logo-dark-bg.svg'
          : 'assets/logo/enersol-logo-white-bg.svg',
      height: height,
      semanticsLabel: 'Enersol',
    );
  }
}
