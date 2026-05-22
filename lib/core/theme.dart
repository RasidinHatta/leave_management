import 'package:flutter/material.dart';

enum AppThemeMode { dark, light }

enum AppPalette {
  amberSunset,
  oceanBreeze,
  forestWalk,
  lavenderDusk,
  slatePro,
  roseGold,
}

class AppAppearance {
  final AppThemeMode mode;
  final AppPalette palette;

  const AppAppearance({
    this.mode = AppThemeMode.dark,
    this.palette = AppPalette.amberSunset,
  });

  bool get isDark => mode == AppThemeMode.dark;

  AppAppearance copyWith({AppThemeMode? mode, AppPalette? palette}) {
    return AppAppearance(
      mode: mode ?? this.mode,
      palette: palette ?? this.palette,
    );
  }
}

class _PaletteColors {
  final Color primary;
  final Color primaryLight;
  final Color primaryDark;
  final Color onPrimary;

  const _PaletteColors({
    required this.primary,
    required this.primaryLight,
    required this.primaryDark,
    required this.onPrimary,
  });
}

class AppColors {
  static AppAppearance _appearance = const AppAppearance();

  static void apply(AppAppearance appearance) {
    _appearance = appearance;
  }

  static bool get isDark => _appearance.isDark;

  static _PaletteColors get _accent {
    switch (_appearance.palette) {
      case AppPalette.oceanBreeze:
        return _PaletteColors(
          primary: Color(0xFF3B82F6),
          primaryLight: Color(0xFF06B6D4),
          primaryDark: Color(0xFF0EA5E9),
          onPrimary: Colors.white,
        );
      case AppPalette.forestWalk:
        return _PaletteColors(
          primary: Color(0xFF10B981),
          primaryLight: Color(0xFF34D399),
          primaryDark: Color(0xFF065F46),
          onPrimary: Colors.white,
        );
      case AppPalette.lavenderDusk:
        return _PaletteColors(
          primary: Color(0xFF8B5CF6),
          primaryLight: Color(0xFFEC4899),
          primaryDark: Color(0xFFA78BFA),
          onPrimary: Colors.white,
        );
      case AppPalette.slatePro:
        return _PaletteColors(
          primary: Color(0xFF475569),
          primaryLight: Color(0xFF64748B),
          primaryDark: Color(0xFF94A3B8),
          onPrimary: Colors.white,
        );
      case AppPalette.roseGold:
        return _PaletteColors(
          primary: Color(0xFFFB7185),
          primaryLight: Color(0xFFF43F5E),
          primaryDark: Color(0xFFFBBF24),
          onPrimary: Colors.white,
        );
      case AppPalette.amberSunset:
        return _PaletteColors(
          primary: Color(0xFFF59E0B),
          primaryLight: Color(0xFFEF4444),
          primaryDark: Color(0xFFF97316),
          onPrimary: Color(0xFFFFFBEB),
        );
    }
  }

  static Color get background => isDark ? Color(0xFF111827) : Color(0xFFF4F6FA);
  static Color get surface => isDark ? Color(0xFF1F2937) : Color(0xFFFFFFFF);
  static Color get surfaceElevated =>
      isDark ? Color(0xFF273244) : Color(0xFFF8FAFC);
  static Color get primary => _accent.primary;
  static Color get primaryLight => _accent.primaryLight;
  static Color get primaryDark => _accent.primaryDark;
  static Color get onPrimary => _accent.onPrimary;
  static Color get success => Color(0xFF10B981);
  static Color get successBg => isDark ? Color(0xFF0D2818) : Color(0xFFDDFBEA);
  static Color get error => Color(0xFFEF4444);
  static Color get errorBg => isDark ? Color(0xFF2D1515) : Color(0xFFFFE4E6);
  static Color get warning => Color(0xFFF59E0B);
  static Color get warningBg => isDark ? Color(0xFF2D2008) : Color(0xFFFEF3C7);
  static Color get textPrimary =>
      isDark ? Color(0xFFFFFBEB) : Color(0xFF111827);
  static Color get textSecondary =>
      isDark ? Color(0xFF9CA3AF) : Color(0xFF4B5563);
  static Color get textMuted => isDark ? Color(0xFF6B7280) : Color(0xFF6B7280);
  static Color get textDisabled =>
      isDark ? Color(0xFF4B5563) : Color(0xFF9CA3AF);
  static Color get border => isDark ? Color(0xFF374151) : Color(0xFFD7DEE8);
}

class AppTheme {
  static ThemeData fromAppearance(AppAppearance appearance) {
    AppColors.apply(appearance);
    return _build(appearance);
  }

  static ThemeData get dark => fromAppearance(AppAppearance());

  static ThemeData _build(AppAppearance appearance) {
    final brightness = appearance.isDark ? Brightness.dark : Brightness.light;
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: AppColors.primary,
        onPrimary: AppColors.onPrimary,
        secondary: AppColors.primaryLight,
        onSecondary: AppColors.onPrimary,
        tertiary: AppColors.primaryDark,
        onTertiary: AppColors.onPrimary,
        surface: AppColors.surface,
        onSurface: AppColors.textPrimary,
        error: AppColors.error,
        onError: Colors.white,
        primaryContainer: AppColors.primary.withValues(alpha: 0.16),
        onPrimaryContainer: AppColors.primaryLight,
        secondaryContainer: AppColors.surfaceElevated,
        onSecondaryContainer: AppColors.textPrimary,
        tertiaryContainer: AppColors.primary.withValues(alpha: 0.12),
        onTertiaryContainer: AppColors.primary,
        errorContainer: AppColors.errorBg,
        onErrorContainer: AppColors.error,
        inverseSurface: appearance.isDark
            ? Color(0xFFE5E7EB)
            : Color(0xFF111827),
        onInverseSurface: appearance.isDark
            ? Color(0xFF111827)
            : Color(0xFFF9FAFB),
        inversePrimary: AppColors.primaryDark,
        shadow: Colors.black,
        scrim: Colors.black,
        outline: AppColors.border,
        outlineVariant: AppColors.border.withValues(alpha: 0.7),
        surfaceBright: appearance.isDark
            ? Color(0xFF273244)
            : Color(0xFFFFFFFF),
        surfaceDim: appearance.isDark ? Color(0xFF111827) : Color(0xFFE5E7EB),
        surfaceContainerLowest: appearance.isDark
            ? Color(0xFF0B1220)
            : Color(0xFFFFFFFF),
        surfaceContainerLow: appearance.isDark
            ? Color(0xFF172033)
            : Color(0xFFF8FAFC),
        surfaceContainer: AppColors.surface,
        surfaceContainerHighest: AppColors.surfaceElevated,
      ),
      cardColor: AppColors.surface,
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: AppColors.border),
        ),
        margin: EdgeInsets.zero,
      ),
      dividerColor: AppColors.border,
      dividerTheme: DividerThemeData(
        color: AppColors.border,
        thickness: 1,
        space: 1,
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: AppColors.primary,
        selectionColor: Color(0x4DD97706),
        selectionHandleColor: AppColors.primary,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceElevated,
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: AppColors.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: AppColors.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: AppColors.error, width: 1.5),
        ),
        labelStyle: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        hintStyle: TextStyle(color: AppColors.textMuted, fontSize: 13),
        errorStyle: TextStyle(color: AppColors.error, fontSize: 11),
        prefixIconColor: AppColors.textSecondary,
        suffixIconColor: AppColors.textSecondary,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.onPrimary,
          disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.4),
          disabledForegroundColor: AppColors.onPrimary.withValues(alpha: 0.6),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          textStyle: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: BorderSide(color: AppColors.primary),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          textStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        ),
      ),
      dataTableTheme: DataTableThemeData(
        headingRowColor: WidgetStateProperty.all(AppColors.surfaceElevated),
        headingTextStyle: TextStyle(
          color: AppColors.textSecondary,
          fontWeight: FontWeight.w600,
          fontSize: 12,
          letterSpacing: 0.5,
        ),
        dataRowColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.hovered)) {
            return AppColors.primary.withValues(alpha: 0.05);
          }
          return AppColors.surface;
        }),
        dataTextStyle: TextStyle(color: AppColors.textPrimary, fontSize: 13),
        dividerThickness: 0,
        columnSpacing: 24,
        horizontalMargin: 16,
        dataRowMinHeight: 44,
        dataRowMaxHeight: 60,
        headingRowHeight: 44,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: AppColors.border),
        ),
        titleTextStyle: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
        contentTextStyle: TextStyle(
          color: AppColors.textSecondary,
          fontSize: 13,
        ),
        elevation: 8,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.surfaceElevated,
        contentTextStyle: TextStyle(color: AppColors.textPrimary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        behavior: SnackBarBehavior.floating,
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AppColors.primary;
          }
          return Colors.transparent;
        }),
        side: BorderSide(color: AppColors.border, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      textTheme: TextTheme(
        titleLarge: TextStyle(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w600,
          fontSize: 18,
        ),
        titleMedium: TextStyle(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w500,
          fontSize: 15,
        ),
        titleSmall: TextStyle(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w500,
          fontSize: 13,
        ),
        bodyLarge: TextStyle(color: AppColors.textPrimary, fontSize: 14),
        bodyMedium: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        bodySmall: TextStyle(color: AppColors.textSecondary, fontSize: 11),
        labelLarge: TextStyle(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w500,
          fontSize: 14,
        ),
        labelMedium: TextStyle(color: AppColors.textSecondary, fontSize: 12),
        labelSmall: TextStyle(color: AppColors.textSecondary, fontSize: 11),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.all(AppColors.border),
        trackColor: WidgetStateProperty.all(Colors.transparent),
        radius: Radius.circular(4),
        thickness: WidgetStateProperty.all(6),
      ),
    );
  }

  static TextTheme scaleTextTheme(TextTheme base, double factor) {
    TextStyle? scale(TextStyle? style) {
      if (style == null || style.fontSize == null) return style;
      return style.copyWith(fontSize: style.fontSize! * factor);
    }

    return base.copyWith(
      displayLarge: scale(base.displayLarge),
      displayMedium: scale(base.displayMedium),
      displaySmall: scale(base.displaySmall),
      headlineLarge: scale(base.headlineLarge),
      headlineMedium: scale(base.headlineMedium),
      headlineSmall: scale(base.headlineSmall),
      titleLarge: scale(base.titleLarge),
      titleMedium: scale(base.titleMedium),
      titleSmall: scale(base.titleSmall),
      bodyLarge: scale(base.bodyLarge),
      bodyMedium: scale(base.bodyMedium),
      bodySmall: scale(base.bodySmall),
      labelLarge: scale(base.labelLarge),
      labelMedium: scale(base.labelMedium),
      labelSmall: scale(base.labelSmall),
    );
  }
}
