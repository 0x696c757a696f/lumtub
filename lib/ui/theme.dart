import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

import '../appearance_settings.dart';

/// Shared spacing and shapes, following PiliNara's compact card layout.
abstract final class AppStyle {
  static const cardSpacing = Space.l;
  static const pagePadding = Space.xl;
  static const radius = Radii.xl;
  static const cardRadius = BorderRadius.all(Radius.circular(radius));
  static const thumbnailRadius = BorderRadius.vertical(top: Radius.circular(radius));
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

/// Material 3 theme built from one seed colour, with PiliNara's flat cards,
/// rounded menus and quiet tooltips.
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
  }
  if (dark && !highContrast) {
    // Flat neutral greys under the colours of the chosen accent.
    scheme = scheme.copyWith(
      surface: const Color(0xFF181818),
      surfaceDim: const Color(0xFF181818),
      surfaceBright: const Color(0xFF313131),
      surfaceContainerLowest: const Color(0xFF131209),
      surfaceContainerLow: const Color(0xFF1F1F1F),
      surfaceContainer: const Color(0xFF1F1F1F),
      surfaceContainerHigh: const Color(0xFF272727),
      surfaceContainerHighest: const Color(0xFF313131),
    );
  }
  if (dark && pureBlack) {
    scheme = scheme.copyWith(surface: Colors.black, surfaceContainerLowest: Colors.black, surfaceContainerLow: const Color(0xFF0E0E0E));
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
  final fallback = fontFamily == bundledFont ? null : const [bundledFont];
  TextStyle font(TextStyle style) => style.copyWith(fontFamily: fontFamily, fontFamilyFallback: fallback);
  // Every button: a visible ring when reached by keyboard, label in
  // semibold on the type scale.
  final focusRing = WidgetStateProperty.resolveWith<BorderSide?>((states) => states.contains(WidgetState.focused) ? BorderSide(color: scheme.primary, width: 2) : null);
  final outlineRing = WidgetStateProperty.resolveWith<BorderSide?>((states) => states.contains(WidgetState.focused)
      ? BorderSide(color: scheme.primary, width: 2)
      : BorderSide(color: states.contains(WidgetState.disabled) ? scheme.onSurface.withValues(alpha: 0.12) : scheme.outlineVariant));
  final buttonText = WidgetStatePropertyAll(font(const TextStyle(fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w600)));
  const buttonPadding = WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.s));
  const buttonShape = WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(Radii.l))));
  final theme = ThemeData(
    useMaterial3: true,
    fontFamily: fontFamily,
    // Characters a chosen Windows font lacks come from the bundled one.
    fontFamilyFallback: fallback,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    visualDensity: VisualDensity.standard,
    appBarTheme: AppBarTheme(
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: dark ? scheme.surfaceContainer : scheme.surfaceContainerLow,
      shape: const RoundedRectangleBorder(borderRadius: AppStyle.cardRadius),
      clipBehavior: Clip.antiAlias,
    ),
    listTileTheme: const ListTileThemeData(
      shape: RoundedRectangleBorder(borderRadius: AppStyle.cardRadius),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: Colors.transparent,
      indicatorColor: scheme.secondaryContainer,
      selectedLabelTextStyle: font(TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.onSurface)),
      unselectedLabelTextStyle: font(TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHigh,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.m),
      border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(Radii.xxxl)), borderSide: BorderSide.none),
      enabledBorder: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(Radii.xxxl)), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(borderRadius: const BorderRadius.all(Radius.circular(Radii.xxxl)), borderSide: BorderSide(color: scheme.primary, width: 1.5)),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: scheme.surfaceContainerLow,
      elevation: 3,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(Radii.xxl))),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: scheme.secondaryContainer,
      contentTextStyle: font(TextStyle(color: scheme.onSecondaryContainer)),
      width: 480,
    ),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 500),
      textStyle: font(const TextStyle(fontSize: 12, height: 16 / 12, color: Colors.white)),
      decoration: const BoxDecoration(color: Color(0xE6424242), borderRadius: BorderRadius.all(Radius.circular(Radii.m))),
    ),
    // Pills, like the segmented buttons beside them: a hairline when off,
    // filled with no outline when on.
    chipTheme: ChipThemeData(
      shape: const StadiumBorder(),
      side: WidgetStateBorderSide.resolveWith((states) => states.contains(WidgetState.selected) ? BorderSide.none : BorderSide(color: scheme.outlineVariant)),
      selectedColor: scheme.secondaryContainer,
      labelStyle: font(TextStyle(fontSize: 14, height: 20 / 14, color: scheme.onSurfaceVariant)),
      secondaryLabelStyle: font(TextStyle(fontSize: 14, height: 20 / 14, color: scheme.onSecondaryContainer, fontWeight: FontWeight.w600)),
      padding: const EdgeInsets.symmetric(horizontal: Space.s),
      labelPadding: const EdgeInsets.symmetric(horizontal: 4),
    ),
    // Drop-down menus (filters, MenuAnchor) match the popup menus.
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(scheme.surfaceContainerLow),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(3),
        shape: const WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(Radii.xl)))),
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: Space.s)),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        side: WidgetStatePropertyAll(BorderSide(color: scheme.outlineVariant)),
        backgroundColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? scheme.secondaryContainer : null),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(style: ButtonStyle(side: focusRing, textStyle: buttonText, padding: buttonPadding, shape: buttonShape)),
    elevatedButtonTheme: ElevatedButtonThemeData(style: ButtonStyle(side: focusRing, textStyle: buttonText, padding: buttonPadding, shape: buttonShape)),
    outlinedButtonTheme: OutlinedButtonThemeData(style: ButtonStyle(side: outlineRing, textStyle: buttonText, padding: buttonPadding, shape: buttonShape)),
    textButtonTheme: TextButtonThemeData(style: ButtonStyle(side: focusRing, textStyle: buttonText, padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.s)), shape: buttonShape)),
    iconButtonTheme: IconButtonThemeData(style: ButtonStyle(side: focusRing)),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant.withValues(alpha: 0.5), space: 1),
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
