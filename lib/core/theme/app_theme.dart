import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

/// The Enersol design system, ported from the admin panel's `styles.scss`.
///
/// Brand runs ember (#E8763A) -> solar amber (#FFC72C), taken from the logo.
/// The web app never uses a flat brand fill; neither do we — [AppColors.brand]
/// is the gradient every accent surface paints with.
class AppColors {
  const AppColors._();

  // ── Brand ────────────────────────────────────────────────────────────────
  static const Color ember = Color(0xFFE8763A);
  static const Color emberMid = Color(0xFFF79C2A);
  static const Color amber = Color(0xFFFFC72C);
  static const Color emberDeep = Color(0xFFD35400);

  static const LinearGradient brand = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [ember, emberMid, amber],
    stops: [0.0, 0.48, 1.0],
  );

  /// Accent gradients used for status chips and tiles, mirroring the web
  /// `--grad-sky` / `--grad-leaf` / `--grad-violet` / `--grad-rose`.
  static const LinearGradient sky = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0EA5E9), Color(0xFF22D3EE)],
  );
  static const LinearGradient leaf = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF059669), Color(0xFF34D399)],
  );
  static const LinearGradient violet = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF7C3AED), Color(0xFFC084FC)],
  );
  static const LinearGradient rose = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFE11D48), Color(0xFFFB7185)],
  );

  // ── Light scheme ─────────────────────────────────────────────────────────
  static const Color lightText1 = Color(0xFF1E293B);
  static const Color lightText2 = Color(0xFF475569);
  static const Color lightText3 = Color(0xFF64748B);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightHairline = Color(0x4794A3B8); // rgba(148,163,184,.28)

  static const List<Color> lightBackdrop = [
    Color(0xFFF7F9FC),
    Color(0xFFEEF2F8),
    Color(0xFFE6ECF5),
  ];

  // ── Dark scheme ──────────────────────────────────────────────────────────
  static const Color darkText1 = Color(0xFFE9EDF5);
  static const Color darkText2 = Color(0xFFA8B2C6);
  static const Color darkText3 = Color(0xFF7D8798);
  static const Color darkSurface = Color(0xFF1A1F2B);
  static const Color darkHairline = Color(0x2994A3B8); // rgba(148,163,184,.16)

  static const List<Color> darkBackdrop = [
    Color(0xFF0B0E15),
    Color(0xFF121620),
    Color(0xFF0D1117),
  ];

  /// The dark chrome — footer nav, drawer, bottom sheets.
  ///
  /// One value, because these three are the same surface seen in three places
  /// and were previously written as three different hexes (0xFF121620,
  /// 0xFF121620 with alpha, and 0xFF161B26). Sliding a sheet up over the nav bar
  /// showed the seam.
  static const Color darkChrome = Color(0xFF121620);

  /// The base slate the hairlines are mixed from.
  static const Color slate = Color(0xFF94A3B8);

  /// Semantic status colours shared by both schemes.
  static const Color success = Color(0xFF059669);
  static const Color warning = Color(0xFFF59E0B);
  static const Color danger = Color(0xFFE11D48);
  static const Color info = Color(0xFF0EA5E9);

  /// The first stop of [violet] — for a solid tint that has to match the
  /// gradient beside it.
  static const Color violetTint = Color(0xFF7C3AED);
}

/// Corner radii — the web app's `--radius-*` tokens.
class AppRadius {
  const AppRadius._();
  static const double sm = 4;
  static const double md = 6;
  static const double lg = 8;
  static const double xl = 10;
  static const double card = 14;
  static const double pill = 999;
}

/// Spacing — the one scale every gap in the app comes from.
///
/// There was no such scale before, and it showed: the same "gap between two
/// cards" was written as 8, 10, 12 and 14 across five screens, and the same
/// screen padding as 12, 14 and 16. Nothing was individually wrong; the effect
/// was that no two screens quite lined up. Reach for the nearest step rather
/// than inventing a number.
class AppSpacing {
  const AppSpacing._();
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;

  /// Horizontal padding of every scrolling screen.
  static const double page = 16;

  /// Gap between two cards in a list.
  static const double gap = 12;
}

class AppTheme {
  const AppTheme._();

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  /// The system bars for a given scheme — dark glyphs on the light backdrop,
  /// light glyphs on the dark one.
  ///
  /// Android and iOS name this the opposite way round: `statusBarIconBrightness`
  /// is the brightness OF THE ICONS, `statusBarBrightness` the brightness of
  /// what sits BEHIND them. Both are set, so the bars are right on either OS.
  static SystemUiOverlayStyle overlayStyle(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    return SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: isDark
          ? AppColors.darkChrome
          : AppColors.lightBackdrop.last,
      systemNavigationBarIconBrightness:
          isDark ? Brightness.light : Brightness.dark,
      systemNavigationBarDividerColor: Colors.transparent,
    );
  }

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    final text1 = isDark ? AppColors.darkText1 : AppColors.lightText1;
    final text2 = isDark ? AppColors.darkText2 : AppColors.lightText2;
    final text3 = isDark ? AppColors.darkText3 : AppColors.lightText3;
    final surface = isDark ? AppColors.darkSurface : AppColors.lightSurface;
    final hairline = isDark ? AppColors.darkHairline : AppColors.lightHairline;

    final scheme = ColorScheme(
      brightness: brightness,
      primary: AppColors.ember,
      onPrimary: Colors.white,
      secondary: AppColors.amber,
      onSecondary: const Color(0xFF1E293B),
      error: AppColors.danger,
      onError: Colors.white,
      surface: surface,
      onSurface: text1,
    );

    // Inter, matching the admin panel's Google-Fonts import. google_fonts
    // caches the file after first fetch and falls back to the platform font
    // when offline, so this stays safe on a cold, network-less start.
    final baseText = GoogleFonts.interTextTheme(
      isDark ? ThemeData.dark().textTheme : ThemeData.light().textTheme,
    ).apply(bodyColor: text1, displayColor: text1);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor:
          isDark ? AppColors.darkBackdrop.first : AppColors.lightBackdrop.first,
      textTheme: baseText.copyWith(
        bodySmall: baseText.bodySmall?.copyWith(color: text3),
        labelSmall: baseText.labelSmall?.copyWith(color: text3),
        titleSmall: baseText.titleSmall?.copyWith(color: text2),
      ),
      dividerColor: hairline,
      dividerTheme: DividerThemeData(color: hairline, thickness: 1, space: 1),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        // MUST BE EXPLICIT. Left unset, Material derives the status-bar icon
        // colour from `backgroundColor` — and a TRANSPARENT bar reads as
        // luminance 0, i.e. "dark", so it asked for WHITE icons and they
        // disappeared into the light backdrop. Worse, the style is global and
        // sticky: opening one of these screens turned the icons white for the
        // whole app, including every screen that draws [AppHeader] instead.
        systemOverlayStyle: overlayStyle(brightness),
        iconTheme: IconThemeData(color: text1),
        titleTextStyle: baseText.titleMedium?.copyWith(
          color: text1,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: BorderSide(color: hairline),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark
            ? Colors.white.withValues(alpha: 0.04)
            : Colors.white.withValues(alpha: 0.72),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        hintStyle: baseText.bodyMedium?.copyWith(color: text3),
        labelStyle: baseText.bodyMedium?.copyWith(color: text2),
        prefixIconColor: text3,
        suffixIconColor: text3,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.xl),
          borderSide: BorderSide(color: hairline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.xl),
          borderSide: BorderSide(color: hairline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.xl),
          borderSide: const BorderSide(color: AppColors.ember, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.xl),
          borderSide: const BorderSide(color: AppColors.danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.xl),
          borderSide: const BorderSide(color: AppColors.danger, width: 1.6),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.ember,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.xl),
          ),
          textStyle: baseText.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: text1,
          minimumSize: const Size.fromHeight(48),
          side: BorderSide(color: hairline),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.xl),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: AppColors.ember),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Colors.white : null,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? AppColors.ember : null,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xl),
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: surface,
        selectedItemColor: AppColors.ember,
        unselectedItemColor: text3,
        type: BottomNavigationBarType.fixed,
        showUnselectedLabels: true,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: isDark
            ? Colors.white.withValues(alpha: 0.06)
            : AppColors.slate.withValues(alpha: 0.12),
        labelStyle: baseText.labelMedium!.copyWith(color: text2),
        side: BorderSide(color: hairline),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: text2,
        textColor: text1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
      ),
    );
  }
}
