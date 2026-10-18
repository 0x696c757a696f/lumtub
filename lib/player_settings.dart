import 'dart:convert';
import 'dart:io';

import 'app_directories.dart';
import 'decoder_status.dart';

class PlayerSettings {
  final String hwdec;
  final String scale;
  final bool deband;
  final bool interpolation;
  final double subtitleScale;
  final int subtitlePosition;
  final String cacheMode;
  final int cacheSeconds;
  final int cacheMemoryMb;
  final bool autoSelectCodec;
  final String? cachePath;
  final int? cacheLimitGb;
  final Map<String, String> customOptions;
  final Map<String, DecoderStatus> decoderResults;

  const PlayerSettings({
    this.hwdec = 'auto-safe',
    this.scale = 'spline36',
    this.deband = false,
    this.interpolation = false,
    this.subtitleScale = 1.0,
    this.subtitlePosition = 100,
    this.cacheMode = 'auto',
    this.cacheSeconds = 30,
    this.cacheMemoryMb = 64,
    this.autoSelectCodec = true,
    this.cachePath,
    this.cacheLimitGb,
    this.customOptions = const {},
    this.decoderResults = const {},
  });

  PlayerSettings copyWith({
    String? hwdec,
    String? scale,
    bool? deband,
    bool? interpolation,
    double? subtitleScale,
    int? subtitlePosition,
    String? cacheMode,
    int? cacheSeconds,
    int? cacheMemoryMb,
    bool? autoSelectCodec,
    String? cachePath,
    bool clearCachePath = false,
    int? cacheLimitGb,
    bool clearCacheLimit = false,
    Map<String, String>? customOptions,
    Map<String, DecoderStatus>? decoderResults,
  }) => PlayerSettings(
        hwdec: hwdec ?? this.hwdec,
        scale: scale ?? this.scale,
        deband: deband ?? this.deband,
        interpolation: interpolation ?? this.interpolation,
        subtitleScale: subtitleScale ?? this.subtitleScale,
        subtitlePosition: subtitlePosition ?? this.subtitlePosition,
        cacheMode: cacheMode ?? this.cacheMode,
        cacheSeconds: cacheSeconds ?? this.cacheSeconds,
        cacheMemoryMb: cacheMemoryMb ?? this.cacheMemoryMb,
        autoSelectCodec: autoSelectCodec ?? this.autoSelectCodec,
        cachePath: clearCachePath ? null : cachePath ?? this.cachePath,
        cacheLimitGb: clearCacheLimit ? null : cacheLimitGb ?? this.cacheLimitGb,
        customOptions: customOptions ?? this.customOptions,
        decoderResults: decoderResults ?? this.decoderResults,
      );

  Map<String, dynamic> toJson() => {
        'hwdec': hwdec,
        'scale': scale,
        'deband': deband,
        'interpolation': interpolation,
        'subtitleScale': subtitleScale,
        'subtitlePosition': subtitlePosition,
        'cacheMode': cacheMode,
        'cacheSeconds': cacheSeconds,
        'cacheMemoryMb': cacheMemoryMb,
        'autoSelectCodec': autoSelectCodec,
        if (cachePath != null) 'cachePath': cachePath,
        if (cacheLimitGb != null) 'cacheLimitGb': cacheLimitGb,
        'customOptions': customOptions,
        'decoderResults': decoderResults.map((codec, status) => MapEntry(codec, status.toJson())),
      };

  factory PlayerSettings.fromJson(Object? raw) {
    if (raw is! Map) return const PlayerSettings();
    String choice(String key, Set<String> allowed, String fallback) {
      final value = raw[key]?.toString();
      return allowed.contains(value) ? value! : fallback;
    }
    int number(String key, int fallback, int min, int max) {
      final value = raw[key];
      final parsed = value is num ? value.toInt() : int.tryParse(value?.toString() ?? '');
      if (parsed == null || parsed < min) return fallback;
      return parsed.clamp(min, max).toInt();
    }
    double decimal(String key, double fallback, double min, double max) {
      final value = raw[key];
      final parsed = value is num ? value.toDouble() : double.tryParse(value?.toString() ?? '');
      return parsed == null ? fallback : parsed.clamp(min, max).toDouble();
    }
    final options = <String, String>{};
    final results = <String, DecoderStatus>{};
    if (raw['customOptions'] is Map) {
      for (final entry in (raw['customOptions'] as Map).entries) {
        final key = entry.key.toString();
        final value = entry.value.toString();
        if (isSafeCustomOption(key, value)) options[key] = value;
      }
    }
    if (raw['decoderResults'] is Map) {
      for (final entry in (raw['decoderResults'] as Map).entries) {
        final codec = entry.key.toString().toLowerCase();
        final status = DecoderStatus.fromJson(entry.value);
        if (DecoderStatus.codecs.contains(codec) && status != null) results[codec] = status;
      }
    }
    final path = raw['cachePath']?.toString();
    return PlayerSettings(
      hwdec: choice('hwdec', {'auto-safe', 'd3d11va', 'no'}, 'auto-safe'),
      scale: choice('scale', {'spline36', 'bilinear', 'lanczos'}, 'spline36'),
      deband: raw['deband'] == true,
      interpolation: raw['interpolation'] == true,
      subtitleScale: decimal('subtitleScale', 1.0, 0.5, 3.0),
      subtitlePosition: number('subtitlePosition', 100, 0, 100),
      cacheMode: choice('cacheMode', {'auto', 'yes', 'no'}, 'auto'),
      cacheSeconds: number('cacheSeconds', 30, 1, 600),
      cacheMemoryMb: number('cacheMemoryMb', 64, 16, 1024),
      autoSelectCodec: raw['autoSelectCodec'] != false,
      cachePath: path != null && path.trim().isNotEmpty ? path : null,
      cacheLimitGb: raw['cacheLimitGb'] == null ? null : number('cacheLimitGb', 1, 1, 100),
      customOptions: options,
      decoderResults: results,
    );
  }

  static bool isSafeCustomOption(String key, String value) {
    const supported = {'deband', 'interpolation', 'scale', 'cscale', 'dscale', 'cache', 'cache-secs', 'demuxer-max-bytes', 'sub-scale', 'sub-pos', 'hwdec'};
    return supported.contains(key) && value.isNotEmpty && value.length <= 80 && !RegExp(r'[\r\n;,]').hasMatch(value);
  }
}

class PlayerSettingsStore {
  final File file;
  PlayerSettingsStore(AppDirectories directories) : file = File('${directories.config.path}${Platform.pathSeparator}player_settings.json');

  Future<PlayerSettings> load() async {
    try {
      return PlayerSettings.fromJson(jsonDecode(await file.readAsString()));
    } catch (_) {
      return const PlayerSettings();
    }
  }

  Future<void> save(PlayerSettings settings) async {
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(settings.toJson()), flush: true);
  }
}
