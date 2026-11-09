import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app/app_controller.dart';
import 'app_directories.dart';
import 'blocked_groups.dart';
import 'app_window.dart';
import 'app_log.dart';
import 'appearance_settings.dart';
import 'ui/skin_paint.dart' show SkinGlass;
import 'keep_awake.dart';
import 'l10n/l10n.dart';
import 'network_proxy.dart';
import 'skins/skin_library.dart';
import 'ui/app_shell.dart';
import 'ui/frame_stats.dart';
import 'ui/app_icons.dart';
import 'ui/motion.dart';
import 'ui/smooth_wheel.dart';
import 'ui/palettes.dart';
import 'ui/theme.dart';
import 'ui/window_chrome.dart';
import 'windows_shell.dart';
import 'device.dart';

Future<void> main() async {
  FrameStats.sinceStart.start();
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) SmoothWheel.install();
  // Before any HTTP client exists, so all of them follow the proxy setting.
  HttpOverrides.global = appHttpOverrides;
  final reportFlutterError = FlutterError.onError;
  FlutterError.onError = (details) {
    logError('UI error', details.exception, details.stack);
    reportFlutterError?.call(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    logError('Unhandled error', error, stack);
    return false;
  };
  // Load the theme before the first frame so the window never flashes the
  // wrong colours.
  // The translations come first: the saved language is only recognised once
  // they say which languages can be chosen.
  try {
    await loadTranslations();
  } catch (e) {
    logError('Could not read the translations', e);
  }
  // Before the skins: a skin's overrides depend on the kind of device.
  await Device.load();
  AppearanceSettingsStore? store;
  var appearance = const AppearanceSettings();
  try {
    final directories = await AppDirectories.create();
    BlockLists.folder = directories.data.path;
    store = AppearanceSettingsStore(directories);
    appearance = await store.load();
    await SkinLibrary.instance.load(folder: directories.skins);
  } catch (_) {
    // Directories are created again, with errors reported, during startup.
  }
  setLanguage(appearance.language);
  runApp(LumtubApp(controller: AppController(appearance: appearance, appearanceStore: store)));
  unawaited(WidgetsBinding.instance.waitUntilFirstFrameRasterized.then((_) => logInfo('First frame shown ${FrameStats.sinceStart.elapsedMilliseconds} ms after start')));
}

class LumtubApp extends StatefulWidget {
  const LumtubApp({super.key, required this.controller});
  final AppController controller;

  @override
  State<LumtubApp> createState() => _LumtubAppState();
}

class _LumtubAppState extends State<LumtubApp> {
  // Building a ColorScheme from a seed is not free; the controller notifies on
  // every search result, so themes are rebuilt only when their inputs change.
  Object? _themeKey;
  late ThemeData _light;
  late ThemeData _dark;
  // Used while Windows' high contrast mode is on.
  late ThemeData _lightContrast;
  late ThemeData _darkContrast;
  late final AppLifecycleListener _lifecycle;
  bool _pausedByMinimize = false;
  WindowsShellSync? _shell;
  // The dark theme and 护眼暖色 can follow the clock or the sun.
  Timer? _clock;
  DateTime _now = DateTime.now();

  void _updateThemes(AppearanceSettings appearance, Color accent) {
    Motion.update(appearance.effectiveMotion);
    // Decoded thumbnails and avatars; pages rebuild them from the disk
    // cache quickly, so few are kept, fewer in 低占用模式.
    PaintingBinding.instance.imageCache
      ..maximumSize = appearance.lowResource ? 120 : 300
      ..maximumSizeBytes = (appearance.lowResource ? 24 : 64) << 20;
    final warmth = appearance.warmthAt(DateTime.now());
    final skin = SkinLibrary.instance.byId(appearance.skin);
    final key = (appearance.themeKey(accent), Motion.reduced, warmth, SkinLibrary.instance.revision, skin, appearance.glassOpacity);
    if (key == _themeKey) return;
    _themeKey = key;
    ThemeData build(Brightness brightness, {bool highContrast = false}) => buildAppTheme(
          accent,
          brightness,
          variant: appearance.schemeVariant,
          pureBlack: appearance.pureBlack,
          compact: appearance.compact,
          fontFamily: appearance.font,
          transition: Motion.reduced ? PageTransition.none : appearance.transition,
          highContrast: highContrast,
          palette: paletteOf(appearance.palette),
          warmth: warmth,
          skin: highContrast ? null : skin?.forBrightness(brightness),
          plain: appearance.lowResource,
        );
    _useFilledIcons(skin?.icons.filled ?? false);
    _useGlass(skin?.glass ?? false ? appearance.glassOpacity.clamp(SkinGlass.min, 1).toDouble() : 1);
    _light = build(Brightness.light);
    _dark = build(Brightness.dark);
    _lightContrast = build(Brightness.light, highContrast: true);
    _darkContrast = build(Brightness.dark, highContrast: true);
  }

  void _skinsChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    final controller = widget.controller;
    _shown = _shownOf(controller);
    controller.addListener(_rebuildIfShownChanged);
    SkinLibrary.instance.addListener(_skinsChanged);
    unawaited(controller.initialize());
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      final appearance = controller.appearance;
      final now = DateTime.now();
      if (appearance.themeModeAt(now) != appearance.themeModeAt(_now) || appearance.warmthAt(now) != appearance.warmthAt(_now)) {
        setState(() => _now = now);
      } else {
        _now = now;
      }
    });
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS || Platform.isAndroid) _shell = WindowsShellSync(controller, WindowsShell());
    if (controller.appearance.systemAccent) unawaited(controller.refreshWindowsAccent());
    // Closing the window ends the process without disposing widgets, so the
    // player and unsaved progress are released here first.
    _lifecycle = AppLifecycleListener(
      onExitRequested: () async {
        await controller.shutdown();
        return AppExitResponse.exit;
      },
      // Minimising hides the window; "pause on minimise" resumes only what it
      // paused itself.
      onHide: () {
        controller.cast.windowHidden = true;
        KeepAwake.hidden = true;
        unawaited(controller.setBackgroundAudioOnly(true));
        // Nothing is drawn while hidden: decoded thumbnails go, and come
        // back from the disk cache when the window does.
        PaintingBinding.instance.imageCache
          ..clear()
          ..clearLiveImages();
        if (controller.playing == null) controller.releaseMemory();
        final player = controller.player;
        if (!controller.preferences.pauseOnMinimize || player == null || !player.state.playing) return;
        _pausedByMinimize = true;
        unawaited(player.pause());
      },
      onShow: () {
        // “Show animations in Windows” may have changed meanwhile.
        if (widget.controller.appearance.motion == MotionPreference.system && Motion.systemPrefersReduced() != Motion.reduced) setState(() => _themeKey = null);
        controller.cast.windowHidden = false;
        KeepAwake.hidden = false;
        unawaited(controller.setBackgroundAudioOnly(false));
        if (!_pausedByMinimize) return;
        _pausedByMinimize = false;
        unawaited(controller.player?.play());
      },
    );
  }

  /// What the window around the pages is built from: the controller
  /// notifies on every list and player change, which the shell listens to
  /// itself, so the app around it rebuilds only when one of these changes.
  Object? _shown;
  static Object _shownOf(AppController controller) => (controller.appearance, controller.accentColor, currentLanguage);

  void _rebuildIfShownChanged() {
    final shown = _shownOf(widget.controller);
    if (shown == _shown) return;
    setState(() => _shown = shown);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_rebuildIfShownChanged);
    SkinLibrary.instance.removeListener(_skinsChanged);
    _lifecycle.dispose();
    _clock?.cancel();
    _shell?.dispose();
    widget.controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Builder(
        builder: (context) {
          final appearance = widget.controller.appearance;
          _updateThemes(appearance, widget.controller.accentColor);
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            title: appName,
            themeMode: appearance.themeModeAt(DateTime.now()),
            // Material's own text (tooltips, dialogs) in the language chosen
            // at start.
            locale: _materialLocale(currentLanguage.locale),
            supportedLocales: {for (final l in AppLanguage.selectable) if (_materialLocale(l.locale) case final locale?) locale}.toList(),
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            theme: _light,
            darkTheme: _dark,
            highContrastTheme: _lightContrast,
            highContrastDarkTheme: _darkContrast,
            // The font size setting scales on top of Windows' text size.
            builder: (context, child) {
              final media = MediaQuery.of(context);
              _matchTitleBar(Theme.of(context));
              return MediaQuery(
                data: media.copyWith(textScaler: _ScaledTextScaler(media.textScaler, appearance.textScale), disableAnimations: media.disableAnimations || Motion.reduced),
                child: WindowChrome(controller: widget.controller, title: appName, child: child!),
              );
            },
            home: _pages,
          );
        },
      );

  late final Widget _pages = AppShell(controller: widget.controller);
}

/// [locale] where Flutter has its own dialogs, date pickers and tooltips
/// in it, else English for those; Lumtub's own text still follows the
/// chosen language.
Locale? _materialLocale(Locale? locale) =>
    locale == null || GlobalMaterialLocalizations.delegate.isSupported(locale) ? locale : const Locale('en');

Object? _titleBar;

/// Switches every icon between outlined and filled, as the skin asks, and
/// redraws the whole window so widgets built earlier pick up the change.
void _useGlass(double opacity) {
  if (SkinGlass.opacity == opacity) return;
  SkinGlass.opacity = opacity;
  _rebuildAll();
}

void _useFilledIcons(bool filled) {
  if (AppIcons.filled == filled) return;
  AppIcons.filled = filled;
  _rebuildAll();
}

void _rebuildAll() {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    void rebuild(Element element) {
      element.markNeedsBuild();
      element.visitChildren(rebuild);
    }

    WidgetsBinding.instance.rootElement?.visitChildren(rebuild);
  });
}

/// The Windows title bar in the page's own colours, so the window reads as
/// one surface in light and dark themes.
void _matchTitleBar(ThemeData theme) {
  if (!Platform.isWindows) return;
  final scheme = theme.colorScheme;
  final caption = theme.extension<AppTones>()?.chrome ?? scheme.surface;
  final key = (caption, scheme.onSurface, scheme.brightness);
  if (key == _titleBar) return;
  _titleBar = key;
  WidgetsBinding.instance.addPostFrameCallback((_) => AppWindow.setTitleBar(
        caption: caption.toARGB32(),
        text: scheme.onSurface.toARGB32(),
        dark: scheme.brightness == Brightness.dark,
      ));
}

class _ScaledTextScaler extends TextScaler {
  const _ScaledTextScaler(this.base, this.factor);
  final TextScaler base;
  final double factor;

  @override
  double scale(double fontSize) => base.scale(fontSize) * factor;

  @override
  double get textScaleFactor => base.scale(1) * factor;

  @override
  bool operator ==(Object other) => other is _ScaledTextScaler && other.base == base && other.factor == factor;

  @override
  int get hashCode => Object.hash(base, factor);
}
