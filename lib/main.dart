import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import 'app/app_controller.dart';
import 'app_directories.dart';
import 'app_log.dart';
import 'appearance_settings.dart';
import 'ui/app_shell.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
  // every search result, so themes are rebuilt only when the accent changes.
  Color? _themeAccent;
  late ThemeData _light;
  late ThemeData _dark;
  late final AppLifecycleListener _lifecycle;

  void _updateThemes(Color accent) {
    if (accent == _themeAccent) return;
    _themeAccent = accent;
    _light = buildAppTheme(accent, Brightness.light);
    _dark = buildAppTheme(accent, Brightness.dark);
  }

  @override
  void initState() {
    super.initState();
    unawaited(widget.controller.initialize());
    // Closing the window ends the process without disposing widgets, so the
    // player and unsaved progress are released here first.
    _lifecycle = AppLifecycleListener(onExitRequested: () async {
      await widget.controller.shutdown();
      return AppExitResponse.exit;
    });
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
          _updateThemes(appearance.accent);
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            title: appName,
            themeMode: appearance.themeMode,
            theme: _light,
            darkTheme: _dark,
            home: child,
          );
        },
        child: AppShell(controller: widget.controller),
      );
}
