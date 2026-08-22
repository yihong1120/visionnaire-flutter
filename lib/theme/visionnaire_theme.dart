import 'package:flutter/material.dart';

class VisionnaireTheme {
  const VisionnaireTheme._();

  static const Color primary = Color(0xFF2563EB);
  static const Color primaryDark = Color(0xFF1E40AF);
  static const Color secondary = Color(0xFF059669);
  static const Color tertiary = Color(0xFFF59E0B);
  static const Color error = Color(0xFFDC2626);

  static ThemeData get light {
    const ColorScheme colors = ColorScheme.light(
      primary: primary,
      onPrimary: Colors.white,
      primaryContainer: Color(0xFFDBEAFE),
      onPrimaryContainer: Color(0xFF1E3A8A),
      secondary: secondary,
      onSecondary: Colors.white,
      secondaryContainer: Color(0xFFD1FAE5),
      onSecondaryContainer: Color(0xFF064E3B),
      tertiary: tertiary,
      onTertiary: Color(0xFF422006),
      tertiaryContainer: Color(0xFFFEF3C7),
      onTertiaryContainer: Color(0xFF78350F),
      error: error,
      onError: Colors.white,
      errorContainer: Color(0xFFFEE4E2),
      onErrorContainer: Color(0xFF7A271A),
      surface: Color(0xFFFAFCFF),
      onSurface: Color(0xFF111827),
      surfaceContainerLowest: Colors.white,
      surfaceContainerLow: Color(0xFFF8FAFC),
      surfaceContainer: Color(0xFFF1F5F9),
      surfaceContainerHigh: Color(0xFFEFF6FF),
      surfaceContainerHighest: Color(0xFFE2E8F0),
      outline: Color(0xFF94A3B8),
      outlineVariant: Color(0xFFDDE5EF),
      shadow: Color(0x180F172A),
      scrim: Color(0x99000000),
    );
    return _build(colors, Brightness.light);
  }

  static ThemeData get dark {
    const ColorScheme colors = ColorScheme.dark(
      primary: Color(0xFF60A5FA),
      onPrimary: Color(0xFF082F49),
      primaryContainer: Color(0xFF1D4ED8),
      onPrimaryContainer: Color(0xFFEFF6FF),
      secondary: Color(0xFF34D399),
      onSecondary: Color(0xFF052E2B),
      secondaryContainer: Color(0xFF047857),
      onSecondaryContainer: Color(0xFFECFDF5),
      tertiary: Color(0xFFFBBF24),
      onTertiary: Color(0xFF422006),
      tertiaryContainer: Color(0xFFB45309),
      onTertiaryContainer: Color(0xFFFEF3C7),
      error: Color(0xFFF87171),
      onError: Color(0xFF450A0A),
      errorContainer: Color(0xFF7F1D1D),
      onErrorContainer: Color(0xFFFFE4E6),
      surface: Color(0xFF101418),
      onSurface: Color(0xFFF5F7FA),
      surfaceContainerLowest: Color(0xFF0B0D10),
      surfaceContainerLow: Color(0xFF151A20),
      surfaceContainer: Color(0xFF1B222B),
      surfaceContainerHigh: Color(0xFF242D38),
      surfaceContainerHighest: Color(0xFF303A46),
      outline: Color(0xFF9AA6B5),
      outlineVariant: Color(0xFF3B4654),
      shadow: Color(0x99000000),
      scrim: Color(0xCC000000),
    );
    return _build(colors, Brightness.dark);
  }

  static ThemeData _build(ColorScheme colors, Brightness brightness) {
    final bool isDark = brightness == Brightness.dark;
    final Color cardColor =
        isDark ? colors.surfaceContainerLow : colors.surfaceContainerLowest;
    final Color selectedFill =
        isDark ? colors.primaryContainer : colors.primaryContainer;
    final Color selectedText =
        isDark ? colors.onPrimaryContainer : colors.primary;
    final Color subtleFill =
        isDark ? colors.surfaceContainer : colors.surfaceContainerLow;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colors,
      scaffoldBackgroundColor: colors.surface,
      canvasColor: colors.surface,
      visualDensity: VisualDensity.standard,
      appBarTheme: AppBarTheme(
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: colors.surface,
        foregroundColor: colors.onSurface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          color: colors.onSurface,
          fontSize: 22,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
        ),
      ),
      cardTheme: CardThemeData(
        color: cardColor,
        elevation: isDark ? 0 : 1,
        margin: EdgeInsets.zero,
        surfaceTintColor: Colors.transparent,
        shadowColor: colors.shadow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: colors.outlineVariant.withValues(alpha: .7)),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: colors.outlineVariant,
        space: 1,
        thickness: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: cardColor,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: colors.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: colors.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: colors.primary, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: colors.error),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: colors.primary,
          foregroundColor: colors.onPrimary,
          minimumSize: const Size(48, 44),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colors.primary,
          minimumSize: const Size(48, 44),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          side: BorderSide(color: colors.outline),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colors.primary,
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
          ),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith<Color?>(
            (Set<WidgetState> states) {
              if (states.contains(WidgetState.selected)) return selectedFill;
              return colors.surfaceContainerLowest;
            },
          ),
          foregroundColor: WidgetStateProperty.resolveWith<Color?>(
            (Set<WidgetState> states) {
              if (states.contains(WidgetState.selected)) return selectedText;
              return colors.onSurface;
            },
          ),
          side: WidgetStateProperty.all<BorderSide>(
            BorderSide(color: colors.outlineVariant),
          ),
          shape: WidgetStateProperty.all<OutlinedBorder>(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          textStyle: WidgetStateProperty.all<TextStyle>(
            const TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0),
          ),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith<Color?>(
          (Set<WidgetState> states) {
            if (states.contains(WidgetState.selected)) return colors.onPrimary;
            return colors.outline;
          },
        ),
        trackColor: WidgetStateProperty.resolveWith<Color?>(
          (Set<WidgetState> states) {
            if (states.contains(WidgetState.selected)) return colors.primary;
            return colors.surfaceContainerHighest;
          },
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: subtleFill,
        selectedColor: colors.primaryContainer,
        disabledColor: colors.surfaceContainer,
        labelStyle: TextStyle(color: colors.onSurface),
        secondaryLabelStyle: TextStyle(color: colors.primary),
        side: BorderSide(color: colors.outlineVariant),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: cardColor,
        surfaceTintColor: Colors.transparent,
        elevation: 6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colors.surface,
        indicatorColor: colors.primaryContainer,
        labelTextStyle: WidgetStateProperty.all<TextStyle>(
          const TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0),
        ),
      ),
      iconTheme: IconThemeData(color: colors.onSurface),
      listTileTheme: ListTileThemeData(
        iconColor: colors.onSurface,
        selectedColor: colors.primary,
        selectedTileColor: colors.primaryContainer.withValues(alpha: 0.5),
      ),
    );
  }
}
