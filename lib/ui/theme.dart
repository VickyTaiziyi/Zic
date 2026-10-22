import 'package:flutter/material.dart';

import '../state/app_kv.dart';

/// Zic design language — "Ink & Signal".
///
/// Derived from the ZCode desktop visual system: a warm near-monochrome
/// stone scale, ink (not blue) as the interactive primary, and a single
/// signal-orange accent reserved for state and brand moments. Surfaces are
/// flat and hairline-bordered; shadows only on floating layers.
///
/// The token NAMES (including the legacy `sky*` accent aliases) are kept
/// stable so the ported feature code compiles untouched; the VALUES are the
/// Zic palette. `sky*` now resolves to the signal-orange ramp.
class ZColors {
  ZColors._();

  // Warm stone scale (matches the ZCode desktop neutrals).
  static const neutral50 = Color(0xFFFAFAF9);
  static const neutral100 = Color(0xFFF5F5F4);
  static const neutral200 = Color(0xFFE7E5E4);
  static const neutral300 = Color(0xFFD6D3D1);
  static const neutral400 = Color(0xFFA8A29E);
  static const neutral500 = Color(0xFF78716C);
  static const neutral600 = Color(0xFF57534E);
  static const neutral700 = Color(0xFF44403C);
  static const neutral800 = Color(0xFF292524);
  static const neutral900 = Color(0xFF1C1917);
  static const neutral950 = Color(0xFF0C0A09);

  // Surfaces.
  static const darkBackground = Color(0xFF131313);
  static const darkCard = Color(0xFF1D1D1D);
  static const darkSidebar = Color(0xFF191919);
  static const darkSecondary = Color(0xFF262626);
  static const lightBackground = Color(0xFFFAFAF9);
  static const lightCard = Color(0xFFFFFFFF);
  static const lightSidebar = Color(0xFFF5F5F4);
  static const lightSecondary = Color(0xFFEFEDEA);

  // Signal-orange brand ramp (the single accent).
  static const accent = Color(0xFFFF8800); // dots, indicators, brand
  static const accentDeep = Color(0xFFEA580C); // pressed / hover
  static const accentText = Color(0xFFC2410C); // accessible on tint (light)
  static const accentTint = Color(0xFFFFF7ED); // chip background (light)
  static const accentTextDark = Color(0xFFFDBA74); // accessible on tint (dark)
  static const accentTintDark = Color(0xFF2A1B0E); // chip background (dark)

  // Legacy accent aliases — remapped from the old sky-blue ramp to the
  // signal-orange ramp. Kept so ported call sites compile and instantly
  // adopt the Zic accent.
  static const sky50 = accentTint;
  static const sky400 = Color(0xFFFB923C);
  static const sky500 = accent;
  static const sky600 = accentDeep;
  static const sky950 = Color(0xFF431407);

  // Status.
  static const danger = Color(0xFFF87171); // dark destructive
  static const dangerLight = Color(0xFFDC2626); // light destructive
  static const success = Color(0xFF34D399); // emerald-400 (dark)
  static const successLight = Color(0xFF16A34A); // green-600 (light)
  static const warning = Color(0xFFFBBF24); // amber-400
  static const warningDeep = Color(0xFFD97706); // amber-600 (light text)

  // Phase pills — tinted, never solid; the dot carries the hue.
  static const pillSuccessBg = Color(0xFFEAF6EE);
  static const pillSuccessFg = Color(0xFF15803D);
  static const pillRunningBg = accentTint;
  static const pillRunningFg = accentText;
  static const pillFailedBg = Color(0xFFFDECEC);
  static const pillFailedFg = Color(0xFFB91C1C);
  static const pillIdleBg = Color(0xFFF0EFED);
  static const pillIdleFg = Color(0xFF57534E);
  static const pillSuccessBgDark = Color(0xFF15251A);
  static const pillSuccessFgDark = Color(0xFF6EE7A0);
  static const pillRunningBgDark = accentTintDark;
  static const pillRunningFgDark = accentTextDark;
  static const pillFailedBgDark = Color(0xFF2C1517);
  static const pillFailedFgDark = Color(0xFFFCA5A5);
  static const pillIdleBgDark = Color(0xFF232323);
  static const pillIdleFgDark = Color(0xFFA8A29E);
}

/// Theme-aware text colors on the Zic stone scale.
class ZInk {
  ZInk._();

  static Color solid(BuildContext c) =>
      _dark(c) ? const Color(0xFFEDECEA) : ZColors.neutral900;
  static Color soft(BuildContext c) =>
      _dark(c) ? const Color(0xFFC9C6C2) : ZColors.neutral600;
  static Color muted(BuildContext c) =>
      _dark(c) ? const Color(0xFF96928D) : ZColors.neutral500;
  static Color faint(BuildContext c) => _dark(c)
      ? const Color(0xFFEDECEA).withValues(alpha: 0.60)
      : ZColors.neutral900.withValues(alpha: 0.60);
  static Color ghost(BuildContext c) => _dark(c)
      ? const Color(0xFFEDECEA).withValues(alpha: 0.30)
      : ZColors.neutral900.withValues(alpha: 0.40);

  static Color tile(BuildContext c) =>
      _dark(c) ? ZColors.darkSecondary : ZColors.lightSecondary;

  static Color card(BuildContext c) =>
      _dark(c) ? ZColors.darkCard : ZColors.lightCard;

  static Color surface(BuildContext c) =>
      _dark(c) ? ZColors.darkBackground : ZColors.lightBackground;

  static Color hairline(BuildContext c) => _dark(c)
      ? const Color(0xFF2E2E2E)
      : ZColors.neutral200;

  static Color codeInlineBg(BuildContext c) =>
      _dark(c) ? ZColors.neutral800 : ZColors.neutral100;

  static Color codeBlockBg(BuildContext c) =>
      _dark(c) ? const Color(0xFF0F0F0F) : ZColors.neutral100;

  static Color codeText(BuildContext c) =>
      _dark(c) ? const Color(0xFFE3E1DE) : ZColors.neutral700;

  /// The brand accent, tuned per mode for legibility.
  static Color accent(BuildContext c) =>
      _dark(c) ? ZColors.accent : ZColors.accentDeep;

  static bool _dark(BuildContext c) =>
      Theme.of(c).brightness == Brightness.dark;
}

/// Corner radii — mobile-tuned from the desktop scale (8/12/16/24).
class ZRadii {
  ZRadii._();
  static const sm = 8.0;
  static const md = 10.0;
  static const lg = 14.0;
  static const xl = 18.0;
  static const sheet = 20.0;
}

/// Shadows are reserved for floating layers (dialogs, popups, toasts);
/// inline surfaces stay flat with hairline borders.
class ZShadows {
  ZShadows._();
  static List<BoxShadow> floating(BuildContext c) => [
        BoxShadow(
          color: _dark(c)
              ? Colors.black.withValues(alpha: 0.55)
              : const Color(0xFF1C1917).withValues(alpha: 0.10),
          blurRadius: 24,
          offset: const Offset(0, 8),
        ),
      ];
  static bool _dark(BuildContext c) =>
      Theme.of(c).brightness == Brightness.dark;
}

/// Light/dark mode, persisted. Zic follows the OS by default.
class ThemeController extends ChangeNotifier {
  static const _key = 'zic_theme_mode';
  ThemeMode _mode = ThemeMode.system;
  ThemeMode get mode => _mode;

  Future<void> load() async {
    switch (await AppKv.instance.getString(_key)) {
      case 'light':
        _mode = ThemeMode.light;
      case 'dark':
        _mode = ThemeMode.dark;
      case 'system':
        _mode = ThemeMode.system;
      default:
        _mode = ThemeMode.system;
    }
    notifyListeners();
  }

  Future<void> setMode(ThemeMode mode) async {
    _mode = mode;
    notifyListeners();
    await AppKv.instance.setString(_key, switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      _ => 'system',
    });
  }

  void cycle() {
    setMode(switch (_mode) {
      ThemeMode.dark => ThemeMode.light,
      ThemeMode.light => ThemeMode.system,
      ThemeMode.system => ThemeMode.dark,
    });
  }
}

ThemeData buildDarkTheme() {
  const scheme = ColorScheme.dark(
    primary: Color(0xFFF5F5F4), // ink — buttons act like ZCode's dark CTAs
    onPrimary: ZColors.neutral950,
    secondary: ZColors.darkSecondary,
    onSecondary: Color(0xFFEDECEA),
    surface: ZColors.darkBackground,
    onSurface: Color(0xFFEDECEA),
    error: ZColors.danger,
    onError: ZColors.neutral950,
    surfaceContainerHighest: ZColors.darkCard,
    outline: Color(0xFF2E2E2E),
  );
  return _base(
    scheme,
    ZColors.darkBackground,
    ZColors.darkCard,
    const Color(0xFF2E2E2E),
    const Color(0xFFEDECEA),
    ZColors.accent,
  );
}

ThemeData buildLightTheme() {
  const scheme = ColorScheme.light(
    primary: ZColors.neutral900, // ink CTAs, like the ZCode desktop buttons
    onPrimary: ZColors.neutral50,
    secondary: ZColors.lightSecondary,
    onSecondary: ZColors.neutral900,
    surface: ZColors.lightBackground,
    onSurface: ZColors.neutral900,
    error: ZColors.dangerLight,
    onError: ZColors.neutral50,
    surfaceContainerHighest: ZColors.lightCard,
    outline: ZColors.neutral200,
  );
  return _base(
    scheme,
    ZColors.lightBackground,
    ZColors.lightCard,
    ZColors.neutral200,
    ZColors.neutral900,
    ZColors.accent,
  );
}

ThemeData _base(ColorScheme scheme, Color background, Color card,
    Color border, Color foreground, Color focus) {
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: background,
    splashFactory: InkSparkle.splashFactory,
    appBarTheme: AppBarTheme(
      backgroundColor: background,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
          color: foreground, fontSize: 17, fontWeight: FontWeight.w600),
      iconTheme: IconThemeData(color: foreground),
    ),
    dividerTheme: DividerThemeData(color: border, thickness: 1, space: 1),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: card,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: scheme.primary,
      contentTextStyle: TextStyle(color: scheme.onPrimary),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: border),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.brightness == Brightness.dark
          ? ZColors.darkSecondary
          : ZColors.neutral100,
      hintStyle: TextStyle(color: foreground.withValues(alpha: 0.40)),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: border)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: border)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: focus, width: 1.5)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: foreground,
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
      ),
    ),
    listTileTheme: ListTileThemeData(
      textColor: foreground,
      iconColor: foreground,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return scheme.onPrimary;
        return scheme.brightness == Brightness.dark
            ? const Color(0xFF96928D)
            : ZColors.neutral300;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return focus;
        return scheme.brightness == Brightness.dark
            ? ZColors.darkSecondary
            : ZColors.neutral200;
      }),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected) ? focus : Colors.transparent),
      side: BorderSide(color: border, width: 1.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    ),
    progressIndicatorTheme:
        ProgressIndicatorThemeData(color: focus, linearTrackColor: border),
  );
}

/// Card visuals for [ZicApp]'s builder-wrapped CardTheme widget
/// (stable across SDKs, unlike ThemeData.cardTheme's param type).
CardThemeData zCardTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  return CardThemeData(
    color: dark ? ZColors.darkCard : ZColors.lightCard,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    margin: EdgeInsets.zero,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: BorderSide(
          color: dark ? const Color(0xFF2E2E2E) : ZColors.neutral200),
    ),
  );
}

/// Dialog visuals for the builder-wrapped DialogTheme widget.
DialogThemeData zDialogTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  return DialogThemeData(
    backgroundColor: dark ? ZColors.darkCard : ZColors.lightCard,
    surfaceTintColor: Colors.transparent,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
  );
}
