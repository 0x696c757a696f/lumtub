import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

import '../appearance_settings.dart';

/// Shared spacing and shapes, following PiliNara's compact card layout.
abstract final class AppStyle {
  static const cardSpacing = 16.0;
  static const pagePadding = 24.0;
  static const radius = 12.0;
  static const cardRadius = BorderRadius.all(Radius.circular(radius));
  static const thumbnailRadius = BorderRadius.vertical(top: Radius.circular(radius));
  static const topBarHeight = 60.0;
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
  return ThemeData(
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
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(24)), borderSide: BorderSide.none),
      enabledBorder: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(24)), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(borderRadius: const BorderRadius.all(Radius.circular(24)), borderSide: BorderSide(color: scheme.primary, width: 1.5)),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: scheme.surfaceContainerLow,
      elevation: 3,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(16))),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: scheme.secondaryContainer,
      contentTextStyle: font(TextStyle(color: scheme.onSecondaryContainer)),
      width: 480,
    ),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 500),
      textStyle: font(const TextStyle(fontSize: 13, color: Colors.white)),
      decoration: const BoxDecoration(color: Color(0xE6424242), borderRadius: BorderRadius.all(Radius.circular(6))),
    ),
    // Pills, like the segmented buttons beside them: a hairline when off,
    // filled with no outline when on.
    chipTheme: ChipThemeData(
      shape: const StadiumBorder(),
      side: WidgetStateBorderSide.resolveWith((states) => states.contains(WidgetState.selected) ? BorderSide.none : BorderSide(color: scheme.outlineVariant)),
      selectedColor: scheme.secondaryContainer,
      labelStyle: font(TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
      secondaryLabelStyle: font(TextStyle(fontSize: 13, color: scheme.onSecondaryContainer, fontWeight: FontWeight.w600)),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      labelPadding: const EdgeInsets.symmetric(horizontal: 4),
    ),
    // Drop-down menus (filters, MenuAnchor) match the popup menus.
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(scheme.surfaceContainerLow),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(3),
        shape: const WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12)))),
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 6)),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        side: WidgetStatePropertyAll(BorderSide(color: scheme.outlineVariant)),
        backgroundColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? scheme.secondaryContainer : null),
      ),
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant.withValues(alpha: 0.5), space: 1),
    expansionTileTheme: const ExpansionTileThemeData(shape: Border(), collapsedShape: Border()),
    pageTransitionsTheme: PageTransitionsTheme(builders: {
      TargetPlatform.windows: builder,
      TargetPlatform.linux: builder,
      TargetPlatform.macOS: builder,
      TargetPlatform.android: builder,
    }),
  );
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
