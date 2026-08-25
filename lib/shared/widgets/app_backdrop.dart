import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_theme.dart';

/// The app-wide background: the admin panel's layered `--app-bg`.
///
/// A linear base with two brand-tinted radial washes bled in from the top
/// corners — the same construction as the web `radial-gradient(...)` stack, so
/// the two products read as one system.
///
/// IT ALSO OWNS THE SYSTEM BARS. Every screen in the app is wrapped in one of
/// these and almost none of them use a Material [AppBar], so without an
/// [AnnotatedRegion] here nothing ever told the OS what colour to paint the
/// status-bar clock and icons — they kept whatever the last AppBar had asked
/// for, which was white, on a backdrop that is nearly white by day.
class AppBackdrop extends StatelessWidget {
  const AppBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = isDark ? AppColors.darkBackdrop : AppColors.lightBackdrop;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: AppTheme.overlayStyle(Theme.of(context).brightness),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: base,
            stops: const [0.0, 0.45, 1.0],
          ),
        ),
        child: Stack(
          children: [
            // Ember wash, upper-left.
            Positioned(
              top: -180,
              left: -120,
              child: _Wash(
                size: 420,
                color: AppColors.ember.withValues(alpha: isDark ? 0.22 : 0.20),
              ),
            ),
            // Cooler counterpoint, upper-right: violet at night, amber by day.
            Positioned(
              top: -160,
              right: -140,
              child: _Wash(
                size: 380,
                color: isDark
                    ? AppColors.violetTint.withValues(alpha: 0.18)
                    : AppColors.amber.withValues(alpha: 0.18),
              ),
            ),
            child,
          ],
        ),
      ),
    );
  }
}

class _Wash extends StatelessWidget {
  const _Wash({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
        ),
      ),
    );
  }
}
