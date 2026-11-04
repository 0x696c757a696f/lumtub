import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

import '../appearance_settings.dart';

/// Shared spacing and shapes: flat, hairline borders, small corners.
abstract final class AppStyle {
  static const cardSpacing = Space.l;
  static const pagePadding = Space.xl;
  static const radius = Radii.l;
  static const cardRadius = BorderRadius.all(Radius.circular(radius));
  /// Video cards are a picture and text on the page, so the picture is
  /// rounded on every corner.
  static const thumbnailRadius = BorderRadius.all(Radius.circular(radius));
  /// Buttons, fields, chips and list rows.
  static const controlRadius = BorderRadius.all(Radius.circular(Radii.m));
  static const topBarHeight = 60.0;
}

/// The only gaps and paddings used: nothing between these steps.
abstract final class Space {
  static const xxs = 2.0;
  static const xs = 4.0;
  static const s = 8.0;
  static const m = 12.0;
  static const l = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
  static const xxxl = 40.0;
  static const huge = 48.0;
}

/// Corner radii. A shape inside another one, less than 32 px from its
/// edge, takes [inner] so both curves run parallel.
abstract final class Radii {
  static const xs = 2.0;
  static const s = 4.0;
  static const m = 6.0;
  static const l = 8.0;
  static const xl = 12.0;
  static const xxl = 16.0;
  static const xxxl = 24.0;

  static double inner(double outer, double gap) {
    final radius = outer - gap;
    return gap < 32 && radius > 2 ? radius : 0;
  }
}

/// Font sizes snap to these steps, each with its own line height.
TextTheme _typeScale(TextTheme base) {
  TextStyle? step(TextStyle? style, double size, double line, {FontWeight? weight}) =>
      style?.copyWith(fontSize: size, height: line / size, fontWeight: weight ?? style.fontWeight, letterSpacing: 0);
  return base.copyWith(
    displayLarge: step(base.displayLarge, 48, 48),
    displayMedium: step(base.displayMedium, 36, 40),
    displaySmall: step(base.displaySmall, 30, 36),
    headlineLarge: step(base.headlineLarge, 30, 36, weight: FontWeight.w600),
    headlineMedium: step(base.headlineMedium, 24, 32, weight: FontWeight.w600),
    headlineSmall: step(base.headlineSmall, 24, 32),
    titleLarge: step(base.titleLarge, 20, 28, weight: FontWeight.w600),
    titleMedium: step(base.titleMedium, 16, 24, weight: FontWeight.w600),
    titleSmall: step(base.titleSmall, 14, 20, weight: FontWeight.w600),
    bodyLarge: step(base.bodyLarge, 16, 24),
    bodyMedium: step(base.bodyMedium, 14, 20),
    bodySmall: step(base.bodySmall, 12, 16),
    labelLarge: step(base.labelLarge, 14, 20, weight: FontWeight.w600),
    labelMedium: step(base.labelMedium, 12, 16, weight: FontWeight.w600),
    labelSmall: step(base.labelSmall, 12, 16),
  );
}

/// Neutral greys (zinc) under one accent colour. The accent marks what is
/// chosen, playing or in progress; everything else is black, white and
/// grey, with hairline borders instead of shadows and tinted surfaces.
abstract final class Neutral {
  static const white = Color(0xFFFFFFFF);
  static const n50 = Color(0xFFFAFAFA);
  static const n100 = Color(0xFFF4F4F5);
  static const n200 = Color(0xFFE4E4E7);
  static const n300 = Color(0xFFD4D4D8);
  static const n400 = Color(0xFFA1A1AA);
  static const n500 = Color(0xFF71717A);
  static const n600 = Color(0xFF52525B);
  static const n700 = Color(0xFF3F3F46);
  static const n800 = Color(0xFF27272A);
  static const n850 = Color(0xFF1F1F23);
  static const n900 = Color(0xFF18181B);
  static const n925 = Color(0xFF111113);
  static const n950 = Color(0xFF09090B);
}

ColorScheme _neutralScheme(ColorScheme tonal, Color accent, Brightness brightness, {required bool pureBlack}) {
  final dark = brightness == Brightness.dark;
  // The accent as chosen, not a toned-down variant of it; text on it is
  // black or white, whichever reads better.
  final onAccent = ThemeData.estimateBrightnessForColor(accent) == Brightness.dark ? Neutral.white : Neutral.n950;
  final accentWash = Color.alphaBlend(accent.withValues(alpha: dark ? 0.18 : 0.10), dark ? Neutral.n950 : Neutral.white);
  if (!dark) {
    return tonal.copyWith(
      primary: accent,
      onPrimary: onAccent,
      primaryContainer: accentWash,
      onPrimaryContainer: Neutral.n950,
      secondary: Neutral.n800,
      onSecondary: Neutral.white,
      secondaryContainer: Neutral.n100,
      onSecondaryContainer: Neutral.n900,
      tertiaryContainer: Neutral.n100,
      onTertiaryContainer: Neutral.n900,
      surface: Neutral.white,
      onSurface: Neutral.n950,
      onSurfaceVariant: Neutral.n600,
      surfaceDim: Neutral.n100,
      surfaceBright: Neutral.white,
      surfaceContainerLowest: Neutral.white,
      surfaceContainerLow: Neutral.n50,
      surfaceContainer: Neutral.n100,
      surfaceContainerHigh: Neutral.n100,
      surfaceContainerHighest: Neutral.n200,
      outline: Neutral.n500,
      outlineVariant: Neutral.n200,
      inverseSurface: Neutral.n900,
      onInverseSurface: Neutral.n50,
      surfaceTint: Colors.transparent,
      shadow: Colors.black,
    );
  }
  final base = pureBlack ? Colors.black : Neutral.n950;
  return tonal.copyWith(
    primary: accent,
    onPrimary: onAccent,
    primaryContainer: accentWash,
    onPrimaryContainer: Neutral.n50,
    secondary: Neutral.n200,
    onSecondary: Neutral.n900,
    secondaryContainer: Neutral.n800,
    onSecondaryContainer: Neutral.n50,
    tertiaryContainer: Neutral.n800,
    onTertiaryContainer: Neutral.n50,
    surface: base,
    onSurface: Neutral.n50,
    onSurfaceVariant: Neutral.n300,
    surfaceDim: base,
    surfaceBright: Neutral.n800,
    surfaceContainerLowest: base,
    surfaceContainerLow: pureBlack ? const Color(0xFF0B0B0C) : Neutral.n925,
    surfaceContainer: Neutral.n900,
    surfaceContainerHigh: Neutral.n850,
    surfaceContainerHighest: Neutral.n800,
    outline: Neutral.n400,
    outlineVariant: Neutral.n800,
    inverseSurface: Neutral.n50,
    onInverseSurface: Neutral.n900,
    surfaceTint: Colors.transparent,
    shadow: Colors.black,
  );
}

/// The app's theme: Flutter's Material widgets, restyled flat and neutral.
ThemeData buildAppTheme(
  Color seed,
  Brightness brightness, {
  DynamicSchemeVariant variant = DynamicSchemeVariant.tonalSpot,
  bool pureBlack = false,
  String? fontFamily,
  PageTransition transition = PageTransition.fade,
  bool highContrast = false,
}) {
  final dark = brightness == Brightness.dark;
  var scheme = ColorScheme.fromSeed(seedColor: seed, brightness: brightness, dynamicSchemeVariant: variant, contrastLevel: highContrast ? 1.0 : 0.0);
  if (highContrast) {
    // Windows' high contrast themes: borders and secondary text as strong as text.
    scheme = scheme.copyWith(outline: scheme.onSurface, outlineVariant: scheme.onSurfaceVariant, surface: dark ? Colors.black : Colors.white);
  } else {
    scheme = _neutralScheme(scheme, seed, brightness, pureBlack: pureBlack);
  }
  final builder = switch (transition) {
    PageTransition.fade => const FadeForwardsPageTransitionsBuilder(),
    PageTransition.zoom => const ZoomPageTransitionsBuilder(),
    PageTransition.slide => const FadeUpwardsPageTransitionsBuilder(),
    PageTransition.cupertino => const CupertinoPageTransitionsBuilder(),
    PageTransition.none => const _NoTransitionsBuilder(),
  };
  // Component styles below are used as they are, not merged with the
  // theme's text theme, so they carry the font themselves.
  // The bundled CJK face draws Western curly quotes full width, so the
  // default text starts with a face holding only proportional ones.
  final family = fontFamily == bundledFont ? quotesFont : fontFamily;
  const fallback = [bundledFont];
  TextStyle font(TextStyle style) => style.copyWith(fontFamily: family, fontFamilyFallback: fallback);
  final border = BorderSide(color: scheme.outlineVariant);
  final focusColor = scheme.onSurface.withValues(alpha: 0.55);
  // Every button: a visible ring when reached by keyboard, label in
  // semibold on the type scale.
  final focusRing = WidgetStateProperty.resolveWith<BorderSide?>((states) => states.contains(WidgetState.focused) ? BorderSide(color: focusColor, width: 2) : null);
  final outlineRing = WidgetStateProperty.resolveWith<BorderSide?>((states) => states.contains(WidgetState.focused)
      ? BorderSide(color: focusColor, width: 2)
      : BorderSide(color: states.contains(WidgetState.disabled) ? scheme.onSurface.withValues(alpha: 0.08) : scheme.outlineVariant));
  final buttonText = WidgetStatePropertyAll(font(const TextStyle(fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w600)));
  const buttonPadding = WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.s));
  const buttonShape = WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: AppStyle.controlRadius));
  const flat = WidgetStatePropertyAll(0.0);
  // A quiet grey wash on hover and press, the same on every control.
  final overlay = WidgetStateProperty.resolveWith<Color?>((states) {
    if (states.contains(WidgetState.pressed)) return scheme.onSurface.withValues(alpha: 0.10);
    if (states.contains(WidgetState.hovered) || states.contains(WidgetState.focused)) return scheme.onSurface.withValues(alpha: 0.06);
    return null;
  });
  // The main button is the text colour filled: black on light, white on
  // dark. The accent stays for what is chosen or playing.
  final solid = ButtonStyle(
    backgroundColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.disabled) ? scheme.onSurface.withValues(alpha: 0.12) : scheme.onSurface),
    foregroundColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.disabled) ? scheme.onSurface.withValues(alpha: 0.38) : scheme.surface),
    overlayColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.pressed) || states.contains(WidgetState.hovered) ? scheme.surface.withValues(alpha: 0.12) : null),
    elevation: flat,
    side: focusRing,
    textStyle: buttonText,
    padding: buttonPadding,
    shape: buttonShape,
  );
  final menuShape = RoundedRectangleBorder(borderRadius: AppStyle.cardRadius, side: border);
  final theme = ThemeData(
    useMaterial3: true,
    fontFamily: family,
    // Characters a chosen Windows font lacks come from the bundled one.
    fontFamilyFallback: fallback,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    canvasColor: scheme.surface,
    visualDensity: VisualDensity.standard,
    // No ink ripples: a flat wash on hover and press.
    splashFactory: NoSplash.splashFactory,
    hoverColor: scheme.onSurface.withValues(alpha: 0.05),
    highlightColor: Colors.transparent,
    focusColor: scheme.onSurface.withValues(alpha: 0.08),
    appBarTheme: AppBarTheme(
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
    ),
    // Panels: the page colour with a hairline round them.
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: scheme.surface,
      shape: RoundedRectangleBorder(borderRadius: AppStyle.cardRadius, side: border),
      clipBehavior: Clip.antiAlias,
    ),
    listTileTheme: ListTileThemeData(
      shape: const RoundedRectangleBorder(borderRadius: AppStyle.controlRadius),
      selectedColor: scheme.onSurface,
      selectedTileColor: scheme.secondaryContainer,
      iconColor: scheme.onSurfaceVariant,
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: Colors.transparent,
      indicatorColor: scheme.secondaryContainer,
      indicatorShape: const RoundedRectangleBorder(borderRadius: AppStyle.controlRadius),
      selectedIconTheme: IconThemeData(color: scheme.onSurface),
      unselectedIconTheme: IconThemeData(color: scheme.onSurfaceVariant),
      selectedLabelTextStyle: font(TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.onSurface)),
      unselectedLabelTextStyle: font(TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      indicatorColor: scheme.secondaryContainer,
      indicatorShape: const RoundedRectangleBorder(borderRadius: AppStyle.controlRadius),
    ),
    // Fields: the page colour, a hairline, a darker line when focused.
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? scheme.surfaceContainerLow : scheme.surface,
      hoverColor: Colors.transparent,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.m),
      border: OutlineInputBorder(borderRadius: AppStyle.controlRadius, borderSide: border),
      enabledBorder: OutlineInputBorder(borderRadius: AppStyle.controlRadius, borderSide: border),
      disabledBorder: OutlineInputBorder(borderRadius: AppStyle.controlRadius, borderSide: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5))),
      focusedBorder: OutlineInputBorder(borderRadius: AppStyle.controlRadius, borderSide: BorderSide(color: focusColor, width: 1.5)),
      hintStyle: font(TextStyle(color: scheme.outline)),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: dark ? scheme.surfaceContainer : scheme.surface,
      elevation: 6,
      shadowColor: Colors.black.withValues(alpha: dark ? 0.6 : 0.25),
      surfaceTintColor: Colors.transparent,
      shape: menuShape,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: dark ? scheme.surfaceContainer : scheme.surface,
      contentTextStyle: font(TextStyle(color: scheme.onSurface, fontSize: 14, height: 20 / 14)),
      actionTextColor: scheme.onSurface,
      closeIconColor: scheme.onSurfaceVariant,
      elevation: 6,
      shape: menuShape,
      width: 480,
    ),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 500),
      textStyle: font(TextStyle(fontSize: 12, height: 16 / 12, color: scheme.onInverseSurface)),
      decoration: BoxDecoration(color: scheme.inverseSurface, borderRadius: AppStyle.controlRadius),
    ),
    // Tags: a hairline when off; the text colour filled when on.
    chipTheme: ChipThemeData(
      shape: const RoundedRectangleBorder(borderRadius: AppStyle.controlRadius),
      side: WidgetStateBorderSide.resolveWith((states) => states.contains(WidgetState.selected) ? BorderSide(color: scheme.onSurface) : border),
      backgroundColor: scheme.surface,
      selectedColor: scheme.onSurface,
      checkmarkColor: scheme.surface,
      showCheckmark: false,
      labelStyle: font(TextStyle(fontSize: 14, height: 20 / 14, color: scheme.onSurface)),
      secondaryLabelStyle: font(TextStyle(fontSize: 14, height: 20 / 14, color: scheme.surface, fontWeight: FontWeight.w600)),
      padding: const EdgeInsets.symmetric(horizontal: Space.s),
      labelPadding: const EdgeInsets.symmetric(horizontal: 4),
      elevation: 0,
      pressElevation: 0,
    ),
    // Drop-down menus (filters, MenuAnchor) match the popup menus.
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(dark ? scheme.surfaceContainer : scheme.surface),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(6),
        shadowColor: WidgetStatePropertyAll(Colors.black.withValues(alpha: dark ? 0.6 : 0.25)),
        shape: WidgetStatePropertyAll(menuShape),
        padding: const WidgetStatePropertyAll(EdgeInsets.all(Space.xs)),
      ),
    ),
    menuButtonTheme: MenuButtonThemeData(style: ButtonStyle(
      shape: const WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: AppStyle.controlRadius)),
      overlayColor: overlay,
    )),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        side: WidgetStatePropertyAll(border),
        shape: const WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: AppStyle.controlRadius)),
        backgroundColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? scheme.secondaryContainer : null),
        foregroundColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? scheme.onSurface : scheme.onSurfaceVariant),
        overlayColor: overlay,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(style: solid),
    elevatedButtonTheme: ElevatedButtonThemeData(style: ButtonStyle(
      elevation: flat,
      backgroundColor: WidgetStatePropertyAll(scheme.surface),
      foregroundColor: WidgetStatePropertyAll(scheme.onSurface),
      overlayColor: overlay,
      side: outlineRing,
      textStyle: buttonText,
      padding: buttonPadding,
      shape: buttonShape,
    )),
    outlinedButtonTheme: OutlinedButtonThemeData(style: ButtonStyle(
      foregroundColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.disabled) ? scheme.onSurface.withValues(alpha: 0.38) : scheme.onSurface),
      overlayColor: overlay,
      side: outlineRing,
      textStyle: buttonText,
      padding: buttonPadding,
      shape: buttonShape,
    )),
    textButtonTheme: TextButtonThemeData(style: ButtonStyle(
      foregroundColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.disabled) ? scheme.onSurface.withValues(alpha: 0.38) : scheme.onSurface),
      overlayColor: overlay,
      side: focusRing,
      textStyle: buttonText,
      padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.s)),
      shape: buttonShape,
    )),
    iconButtonTheme: IconButtonThemeData(style: ButtonStyle(
      side: focusRing,
      overlayColor: overlay,
      shape: const WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: AppStyle.controlRadius)),
    )),
    // A plain toggle: white knob of one size on a grey or accent track.
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.disabled) ? scheme.surface.withValues(alpha: 0.7) : Neutral.white),
      trackColor: WidgetStateProperty.resolveWith((states) {
        final on = states.contains(WidgetState.selected);
        final color = on ? scheme.primary : (dark ? Neutral.n700 : Neutral.n200);
        return states.contains(WidgetState.disabled) ? color.withValues(alpha: 0.4) : color;
      }),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      thumbIcon: const WidgetStatePropertyAll(Icon(null)),
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    checkboxTheme: CheckboxThemeData(
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(Radii.s))),
      side: BorderSide(color: scheme.outline, width: 1.5),
      fillColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? scheme.onSurface : null),
      checkColor: WidgetStatePropertyAll(scheme.surface),
    ),
    radioTheme: RadioThemeData(fillColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? scheme.onSurface : scheme.outline)),
    sliderTheme: SliderThemeData(
      trackHeight: 4,
      activeTrackColor: scheme.primary,
      inactiveTrackColor: scheme.surfaceContainerHighest,
      thumbColor: scheme.primary,
      overlayShape: SliderComponentShape.noOverlay,
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7, elevation: 0, pressedElevation: 0),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: scheme.primary, linearTrackColor: scheme.surfaceContainerHighest, circularTrackColor: Colors.transparent),
    tabBarTheme: TabBarThemeData(
      labelColor: scheme.onSurface,
      unselectedLabelColor: scheme.onSurfaceVariant,
      indicatorColor: scheme.onSurface,
      dividerColor: scheme.outlineVariant,
      overlayColor: overlay,
      labelStyle: font(const TextStyle(fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w600)),
      unselectedLabelStyle: font(const TextStyle(fontSize: 14, height: 20 / 14)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: dark ? scheme.surfaceContainerLow : scheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 12,
      shadowColor: Colors.black.withValues(alpha: dark ? 0.7 : 0.3),
      shape: RoundedRectangleBorder(borderRadius: const BorderRadius.all(Radius.circular(Radii.xl)), side: border),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: dark ? scheme.surfaceContainerLow : scheme.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: const BorderRadius.vertical(top: Radius.circular(Radii.xl)), side: border),
    ),
    drawerTheme: DrawerThemeData(backgroundColor: scheme.surface, surfaceTintColor: Colors.transparent, shape: const RoundedRectangleBorder()),
    badgeTheme: BadgeThemeData(backgroundColor: scheme.primary, textColor: scheme.onPrimary),
    scrollbarTheme: ScrollbarThemeData(
      thickness: const WidgetStatePropertyAll(6),
      radius: const Radius.circular(3),
      thumbColor: WidgetStateProperty.resolveWith((states) => scheme.onSurface.withValues(alpha: states.contains(WidgetState.dragged) || states.contains(WidgetState.hovered) ? 0.35 : 0.18)),
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1, thickness: 1),
    expansionTileTheme: const ExpansionTileThemeData(shape: Border(), collapsedShape: Border()),
    pageTransitionsTheme: PageTransitionsTheme(builders: {
      TargetPlatform.windows: builder,
      TargetPlatform.linux: builder,
      TargetPlatform.macOS: builder,
      TargetPlatform.android: builder,
    }),
  );
  return theme.copyWith(textTheme: _typeScale(theme.textTheme));
}

class _NoTransitionsBuilder extends PageTransitionsBuilder {
  const _NoTransitionsBuilder();

  @override
  Widget buildTransitions<T>(PageRoute<T> route, BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation, Widget child) => child;
}

extension ThemeShortcuts on BuildContext {
  ColorScheme get colors => Theme.of(this).colorScheme;
  TextTheme get text => Theme.of(this).textTheme;
}
