import 'package:flutter/material.dart';

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
ThemeData buildAppTheme(Color seed, Brightness brightness) {
  final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: brightness);
  final dark = brightness == Brightness.dark;
  return ThemeData(
    useMaterial3: true,
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
      selectedLabelTextStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.onSurface),
      unselectedLabelTextStyle: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
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
      contentTextStyle: TextStyle(color: scheme.onSecondaryContainer),
      width: 480,
    ),
    tooltipTheme: const TooltipThemeData(
      waitDuration: Duration(milliseconds: 500),
      textStyle: TextStyle(fontSize: 13, color: Colors.white),
      decoration: BoxDecoration(color: Color(0xE6616161), borderRadius: BorderRadius.all(Radius.circular(4))),
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant.withValues(alpha: 0.5), space: 1),
    expansionTileTheme: const ExpansionTileThemeData(shape: Border(), collapsedShape: Border()),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
      TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
    }),
  );
}

extension ThemeShortcuts on BuildContext {
  ColorScheme get colors => Theme.of(this).colorScheme;
  TextTheme get text => Theme.of(this).textTheme;
}
