import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';

import 'app/app_controller.dart';
import 'app_directories.dart';
import 'app_log.dart';
import 'appearance_settings.dart';
import 'network_proxy.dart';
import 'ui/app_shell.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Before any HTTP client exists, so all of them follow the proxy setting.
  HttpOverrides.global = appHttpOverrides;
  final reportFlutterError = FlutterError.onError;
  FlutterError.onError = (details) {
    logError('界面错误', details.exception, details.stack);
    reportFlutterError?.call(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    logError('未处理的错误', error, stack);
    return false;
  };
  // Load the theme before the first frame so the window never flashes the
  // wrong colours.
  AppearanceSettingsStore? store;
  var appearance = const AppearanceSettings();
  try {
    store = AppearanceSettingsStore(await AppDirectories.create());
    appearance = await store.load();
  } catch (_) {
    // Directories are created again, with errors reported, during startup.
  }
  runApp(YtPlusApp(controller: AppController(appearance: appearance, appearanceStore: store)));
}

class YtPlusApp extends StatefulWidget {
  const YtPlusApp({super.key, required this.controller});
  final AppController controller;

  @override
  State<YtPlusApp> createState() => _YtPlusAppState();
}

class _YtPlusAppState extends State<YtPlusApp> {
  // Building a ColorScheme from a seed is not free; the controller notifies on
  // every search result, so themes are rebuilt only when their inputs change.
  Object? _themeKey;
  late ThemeData _light;
  late ThemeData _dark;
  late final AppLifecycleListener _lifecycle;
  bool _pausedByMinimize = false;

  void _updateThemes(AppearanceSettings appearance, Color accent) {
    final key = appearance.themeKey(accent);
    if (key == _themeKey) return;
    _themeKey = key;
    ThemeData build(Brightness brightness) => buildAppTheme(
          accent,
          brightness,
          variant: appearance.schemeVariant,
          pureBlack: appearance.pureBlack,
          fontFamily: appearance.fontFamily,
          transition: appearance.transition,
        );
    _light = build(Brightness.light);
    _dark = build(Brightness.dark);
  }

  @override
  void initState() {
    super.initState();
    final controller = widget.controller;
    unawaited(controller.initialize());
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
        final player = controller.player;
        if (!controller.preferences.pauseOnMinimize || player == null || !player.state.playing) return;
        _pausedByMinimize = true;
        unawaited(player.pause());
      },
      onShow: () {
        if (!_pausedByMinimize) return;
        _pausedByMinimize = false;
        unawaited(controller.player?.play());
      },
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    widget.controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: widget.controller,
        builder: (context, child) {
          final appearance = widget.controller.appearance;
          _updateThemes(appearance, widget.controller.accentColor);
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            title: appName,
            themeMode: appearance.themeMode,
            theme: _light,
            darkTheme: _dark,
            // The font size setting scales on top of Windows' text size.
            builder: (context, child) {
              final media = MediaQuery.of(context);
              return MediaQuery(
                data: media.copyWith(textScaler: _ScaledTextScaler(media.textScaler, appearance.textScale)),
                child: child!,
              );
            },
            home: child,
          );
        },
        child: AppShell(controller: widget.controller),
      );
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
