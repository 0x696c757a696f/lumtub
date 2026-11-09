import 'flat_press.dart';
import 'dart:ui' show lerpDouble;

import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

import '../appearance_settings.dart';
import '../skins/skin.dart';
import 'palettes.dart';
import 'skin_paint.dart';
import 'warm_layer.dart';

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
  bool compact = false,
  String? fontFamily,
  PageTransition transition = PageTransition.fade,
  bool highContrast = false,
  Palette? palette,
  double warmth = 0,
  Skin? skin,
  bool plain = false,
}) {
  if (skin != null) {
    brightness = skin.brightness;
    highContrast = false;
    final c = skin.colors;
    final tones = PaletteTones(c.page, c.text, c.accent, card: c.card, indicator: c.selected, chrome: c.chrome, glow: c.tint);
    palette = Palette('skin:${skin.id}', skin.id, '', tones, tones, strong: c.strong);
  }
  final dark = brightness == Brightness.dark;
  final shape = skin?.shape;
  final controlRadius = BorderRadius.circular(shape?.controlRadius ?? Radii.m);
  final cardRadius = BorderRadius.circular(shape?.cardRadius ?? Radii.l);
  final dialogRadius = BorderRadius.circular(shape?.cardRadius ?? Radii.xl);
  // A palette brings its own accent for each mode.
  if (palette != null && !highContrast) seed = palette.of(brightness).accent;
  var scheme = ColorScheme.fromSeed(seedColor: seed, brightness: brightness, dynamicSchemeVariant: variant, contrastLevel: highContrast ? 1.0 : 0.0);
  if (highContrast) {
    // Windows' high contrast themes: borders and secondary text as strong as text.
    scheme = scheme.copyWith(outline: scheme.onSurface, outlineVariant: scheme.onSurfaceVariant, surface: dark ? Colors.black : Colors.white);
  } else if (palette != null) {
    scheme = paletteScheme(scheme, palette, brightness, pureBlack: (skin == null || skin.followsThemeMode) && pureBlack);
    if (skin != null) {
      final c = skin.colors;
      scheme = scheme.copyWith(
        onPrimary: c.onAccent,
        onSurfaceVariant: c.muted,
        outline: c.muted,
        outlineVariant: c.border,
        onSecondaryContainer: c.onSelected,
      );
    }
  } else {
    scheme = _neutralScheme(scheme, seed, brightness, pureBlack: pureBlack);
  }
  var chrome = highContrast || (skin != null && skin.followsThemeMode && dark && pureBlack) ? null : skin != null ? skin.colors.chrome : paletteChrome(palette, brightness, pureBlack: pureBlack);
  if (warmth > 0 && !highContrast) {
    scheme = warmScheme(scheme, warmth);
    if (chrome != null) chrome = warmColor(chrome, warmth);
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
  final chosen = skin?.font ?? fontFamily;
  final family = chosen == bundledFont ? quotesFont : chosen;
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
  final buttonShape = WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: controlRadius));
  const flat = WidgetStatePropertyAll(0.0);
  // A quiet grey wash on hover and press, the same on every control.
  final overlay = WidgetStateProperty.resolveWith<Color?>((states) {
    if (states.contains(WidgetState.pressed)) return scheme.onSurface.withValues(alpha: 0.18);
    if (states.contains(WidgetState.hovered) || states.contains(WidgetState.focused)) return scheme.onSurface.withValues(alpha: 0.08);
    return null;
  });
  // The main button is the text colour filled: black on light, white on
  // dark. The accent stays for what is chosen or playing.
  final solid = ButtonStyle(
    backgroundColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.disabled) ? scheme.onSurface.withValues(alpha: 0.12) : scheme.onSurface),
    foregroundColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.disabled) ? scheme.onSurface.withValues(alpha: 0.38) : scheme.surface),
    overlayColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.pressed)
        ? scheme.surface.withValues(alpha: 0.26)
        : states.contains(WidgetState.hovered)
            ? scheme.surface.withValues(alpha: 0.14)
            : null),
    elevation: flat,
    side: focusRing,
    textStyle: buttonText,
    padding: buttonPadding,
    shape: buttonShape,
  );
  // A skin's buttons paint their own surface under the label.
  ButtonStyle skinned(ButtonStyle style, SkinSurface? surface, Color? text) {
    if (surface == null) return style;
    final radius = surface.radius ?? controlRadius.topLeft.x;
    return style.copyWith(
      backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
      foregroundColor: text == null ? null : WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.disabled) ? text.withValues(alpha: 0.45) : text),
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      side: focusRing,
      shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius))),
      backgroundBuilder: (context, states, child) {
        final pressed = states.contains(WidgetState.pressed);
        final hovered = states.contains(WidgetState.hovered);
        // A skin that gives no pressed or hover look still answers: a
        // darker or lighter wash over its own surface.
        final wash = pressed && surface.pressed == null
            ? Colors.black.withValues(alpha: 0.16)
            : hovered && !pressed && surface.hover == null
                ? Colors.white.withValues(alpha: 0.14)
                : null;
        return DecoratedBox(
          decoration: SurfaceDecoration.of(context, surface.forState(hovered: hovered, pressed: pressed), radius: radius),
          position: DecorationPosition.background,
          child: DecoratedBox(
            decoration: BoxDecoration(color: wash, borderRadius: BorderRadius.circular(radius)),
            child: Opacity(opacity: states.contains(WidgetState.disabled) ? 0.5 : 1, child: child),
          ),
        );
      },
    );
  }

  final menuShape = RoundedRectangleBorder(borderRadius: cardRadius, side: border);
  final theme = ThemeData(
    useMaterial3: true,
    fontFamily: family,
    // Characters a chosen Windows font lacks come from the bundled one.
    fontFamilyFallback: fallback,
    colorScheme: scheme,
    // A skin paints the page itself, under every page (WindowChrome).
    scaffoldBackgroundColor: skin == null ? scheme.surface : Colors.transparent,
    // A skin's icon finish (emboss, gel, glow); left out in Low resource mode.
    iconTheme: IconThemeData(color: dark ? Colors.white : Colors.black87, shadows: plain ? null : skin?.icons.shadows(brightness, scheme.primary)),
    canvasColor: scheme.surface,
    visualDensity: compact ? VisualDensity.compact : VisualDensity.standard,
    // No ripples: a flat wash that comes in at once on press.
    splashFactory: skin?.press == 'ripple' ? InkRipple.splashFactory : FlatPress.splashFactory,
    splashColor: switch (skin?.press) {
      null => scheme.onSurface.withValues(alpha: 0.14),
      'glow' => scheme.primary.withValues(alpha: 0.38),
      'ripple' => scheme.onSurface.withValues(alpha: 0.16),
      _ => Color.alphaBlend(scheme.primary.withValues(alpha: 0.18), scheme.onSurface.withValues(alpha: 0.08)),
    },
    // Hover has to show on every row and button, on a skin's busy page too.
    hoverColor: skin == null ? scheme.onSurface.withValues(alpha: 0.07) : Color.alphaBlend(scheme.primary.withValues(alpha: 0.10), scheme.onSurface.withValues(alpha: 0.04)),
    highlightColor: Colors.transparent,
    focusColor: skin == null ? scheme.onSurface.withValues(alpha: 0.10) : scheme.primary.withValues(alpha: 0.16),
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
      color: skin?.panel?.baseColor ?? scheme.surface,
      shape: RoundedRectangleBorder(borderRadius: cardRadius, side: border),
      clipBehavior: Clip.antiAlias,
    ),
    listTileTheme: ListTileThemeData(
      shape: RoundedRectangleBorder(borderRadius: controlRadius),
      selectedColor: scheme.onSurface,
      selectedTileColor: scheme.secondaryContainer,
      iconColor: scheme.onSurfaceVariant,
      dense: compact ? true : null,
      minVerticalPadding: compact ? 2 : null,
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: Colors.transparent,
      indicatorColor: scheme.secondaryContainer,
      indicatorShape: RoundedRectangleBorder(borderRadius: controlRadius),
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
      indicatorShape: RoundedRectangleBorder(borderRadius: controlRadius),
    ),
    // Fields: the page colour, a hairline, a darker line when focused.
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? scheme.surfaceContainerLow : scheme.surface,
      hoverColor: Colors.transparent,
      isDense: true,
      contentPadding: EdgeInsets.symmetric(horizontal: Space.m, vertical: compact ? Space.s : Space.m),
      border: OutlineInputBorder(borderRadius: controlRadius, borderSide: border),
      enabledBorder: OutlineInputBorder(borderRadius: controlRadius, borderSide: border),
      disabledBorder: OutlineInputBorder(borderRadius: controlRadius, borderSide: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5))),
      focusedBorder: OutlineInputBorder(borderRadius: controlRadius, borderSide: BorderSide(color: focusColor, width: 1.5)),
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
      decoration: BoxDecoration(color: scheme.inverseSurface, borderRadius: controlRadius),
    ),
    // Tags: a hairline when off; the text colour filled when on.
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: controlRadius),
      side: WidgetStateBorderSide.resolveWith((states) => states.contains(WidgetState.selected)
          ? BorderSide(color: skin?.chipSelected?.border ?? skin?.chipSelected?.baseColor ?? scheme.onSurface)
          : skin?.chip?.border != null ? BorderSide(color: skin!.chip!.border!) : border),
      backgroundColor: skin?.chip?.baseColor ?? scheme.surface,
      selectedColor: skin?.chipSelected?.baseColor ?? scheme.onSurface,
      checkmarkColor: scheme.surface,
      showCheckmark: false,
      // A selected chip is filled with the text colour, so its label
      // turns to the page colour to stay readable.
      labelStyle: font(TextStyle(
        fontSize: 14,
        height: 20 / 14,
        color: WidgetStateColor.resolveWith((states) => states.contains(WidgetState.selected) ? skin?.chipSelectedText ?? scheme.surface : skin?.buttonText ?? scheme.onSurface),
      )),
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
      shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: controlRadius)),
      overlayColor: overlay,
    )),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        side: WidgetStatePropertyAll(border),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: controlRadius)),
        backgroundColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? scheme.secondaryContainer : null),
        foregroundColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? scheme.onSurface : scheme.onSurfaceVariant),
        overlayColor: overlay,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(style: skinned(solid, skin?.primaryButton, skin?.primaryButtonText ?? scheme.onPrimary)),
    elevatedButtonTheme: ElevatedButtonThemeData(style: skinned(ButtonStyle(
      elevation: flat,
      backgroundColor: WidgetStatePropertyAll(scheme.surface),
      foregroundColor: WidgetStatePropertyAll(scheme.onSurface),
      overlayColor: overlay,
      side: outlineRing,
      textStyle: buttonText,
      padding: buttonPadding,
      shape: buttonShape,
    ), skin?.button, skin?.buttonText ?? scheme.onSurface)),
    outlinedButtonTheme: OutlinedButtonThemeData(style: skinned(ButtonStyle(
      foregroundColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.disabled) ? scheme.onSurface.withValues(alpha: 0.38) : scheme.onSurface),
      overlayColor: overlay,
      side: outlineRing,
      textStyle: buttonText,
      padding: buttonPadding,
      shape: buttonShape,
    ), skin?.button, skin?.buttonText ?? scheme.onSurface)),
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
      shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: controlRadius)),
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
      shape: RoundedRectangleBorder(borderRadius: dialogRadius, side: border),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: dark ? scheme.surfaceContainerLow : scheme.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: dialogRadius.topLeft), side: border),
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
  var text = _typeScale(theme.textTheme);
  if (skin?.displayFont case final display?) {
    TextStyle? d(TextStyle? style) => style?.copyWith(fontFamily: display, fontFamilyFallback: [if (family != null) family, bundledFont]);
    text = text.copyWith(
      displayLarge: d(text.displayLarge),
      displayMedium: d(text.displayMedium),
      displaySmall: d(text.displaySmall),
      headlineLarge: d(text.headlineLarge),
      headlineMedium: d(text.headlineMedium),
      headlineSmall: d(text.headlineSmall),
      titleLarge: d(text.titleLarge),
    );
  }
  return theme.copyWith(textTheme: text, extensions: [AppTones(chrome: chrome, warmth: highContrast ? 0 : warmth), SkinTheme(skin)]);
}

/// What the colour scheme does not carry: the palette's top bar and side
/// rail, and how warm 护眼暖色 makes pictures and video.
class AppTones extends ThemeExtension<AppTones> {
  const AppTones({this.chrome, this.warmth = 0});
  final Color? chrome;
  final double warmth;

  @override
  AppTones copyWith({Color? chrome, double? warmth}) => AppTones(chrome: chrome ?? this.chrome, warmth: warmth ?? this.warmth);

  @override
  AppTones lerp(AppTones? other, double t) => AppTones(
        chrome: Color.lerp(chrome, other?.chrome, t),
        warmth: lerpDouble(warmth, other?.warmth ?? 0, t)!,
      );
}

/// The skin the theme was built from, if any.
class SkinTheme extends ThemeExtension<SkinTheme> {
  const SkinTheme(this.skin);
  final Skin? skin;

  @override
  SkinTheme copyWith({Skin? skin}) => SkinTheme(skin ?? this.skin);

  @override
  SkinTheme lerp(SkinTheme? other, double t) => t < 0.5 ? this : other ?? this;
}

class _NoTransitionsBuilder extends PageTransitionsBuilder {
  const _NoTransitionsBuilder();

  @override
  Widget buildTransitions<T>(PageRoute<T> route, BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation, Widget child) => child;
}

extension ThemeShortcuts on BuildContext {
  ColorScheme get colors => Theme.of(this).colorScheme;
  TextTheme get text => Theme.of(this).textTheme;
  AppTones get tones => Theme.of(this).extension<AppTones>() ?? const AppTones();
  Skin? get skin => Theme.of(this).extension<SkinTheme>()?.skin;
  /// Corners of cards and of thumbnails, from the skin when there is one.
  BorderRadius get cardRadius => switch (skin?.shape.cardRadius) { final r? => BorderRadius.circular(r), null => AppStyle.cardRadius };
  BorderRadius get thumbnailRadius => switch (skin?.shape.thumbnailRadius ?? skin?.shape.cardRadius) { final r? => BorderRadius.circular(r), null => AppStyle.thumbnailRadius };
  BorderRadius get controlRadius => switch (skin?.shape.controlRadius) { final r? => BorderRadius.circular(r), null => AppStyle.controlRadius };
  /// Multiplied into thumbnails and avatars under 护眼暖色, none otherwise.
  Color? get pictureWarmth {
    final w = tones.warmth;
    return w <= 0.001 ? null : WarmLayer.tint(w);
  }
}
