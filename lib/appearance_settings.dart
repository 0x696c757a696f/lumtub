import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import 'app_directories.dart';

/// Seed colours offered in Settings; the first is the default.
const accentChoices = <(String, Color)>[
  ('YouTube 红', Color(0xFFE53935)),
  ('青绿', Color(0xFF26A69A)),
  ('天蓝', Color(0xFF1E88E5)),
  ('紫罗兰', Color(0xFF7E57C2)),
  ('琥珀', Color(0xFFFFB300)),
  ('粉红', Color(0xFFEC407A)),
];

class AppearanceSettings {
  final ThemeMode themeMode;
  final int accentIndex;

  const AppearanceSettings({this.themeMode = ThemeMode.system, this.accentIndex = 0});

  Color get accent => accentChoices[accentIndex].$2;

  AppearanceSettings copyWith({ThemeMode? themeMode, int? accentIndex}) => AppearanceSettings(
        themeMode: themeMode ?? this.themeMode,
        accentIndex: accentIndex ?? this.accentIndex,
      );

  Map<String, dynamic> toJson() => {'themeMode': themeMode.name, 'accentIndex': accentIndex};

  factory AppearanceSettings.fromJson(Object? raw) {
    if (raw is! Map) return const AppearanceSettings();
    final mode = ThemeMode.values.where((m) => m.name == raw['themeMode']).firstOrNull ?? ThemeMode.system;
    final index = raw['accentIndex'];
    return AppearanceSettings(
      themeMode: mode,
      accentIndex: index is int && index >= 0 && index < accentChoices.length ? index : 0,
    );
  }
}

class AppearanceSettingsStore {
  final File file;
  AppearanceSettingsStore(AppDirectories directories) : file = File('${directories.config.path}${Platform.pathSeparator}appearance.json');

  Future<AppearanceSettings> load() async {
    try {
      return AppearanceSettings.fromJson(jsonDecode(await file.readAsString()));
    } catch (_) {
      return const AppearanceSettings();
    }
  }

  Future<void> save(AppearanceSettings settings) async {
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(settings.toJson()), flush: true);
  }
}
