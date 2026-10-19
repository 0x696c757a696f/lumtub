import 'dart:convert';
import 'dart:io';

import 'app_directories.dart';
import 'decoder_status.dart';

/// Heights offered in the quality menu; 0 means automatic.
const qualityHeights = [0, 2160, 1440, 1080, 720, 480, 360];

/// Speeds offered before the user edits the list, as in PiliNara.
const defaultSpeeds = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 3.0];

/// The video codec to ask YouTube for first.
enum CodecPreference {
  auto('自动（省资源优先）'),
  avc1('H.264 (AVC)'),
  vp9('VP9'),
  av01('AV1'),
  any('不限（画质优先）');

  const CodecPreference(this.label);
  final String label;
}

enum AudioQuality {
  best('最高'),
  medium('中等（≤128 kbps）'),
  low('省流（≤64 kbps）');

  const AudioQuality(this.label);
  final String label;
}

/// What happens when a video ends. Named and ordered like PiliNara's
/// `PlayRepeat`.
enum PlayOrder {
  pause('播完暂停'),
  listOrder('顺序播放'),
  singleCycle('单个循环'),
  listCycle('列表循环'),
  autoPlayRelated('自动连播');

  const PlayOrder(this.label);
  final String label;
}

enum SubtitleMode {
  off('不自动开启'),
  manual('有人工字幕时开启'),
  always('总是开启（含自动生成字幕）');

  const SubtitleMode(this.label);
  final String label;
}

enum SubtitleLanguage {
  zh('中文优先', '(zh|en).*', 'zh-Hans,zh-CN,zh-SG,zh,zh-Hant,zh-TW,zh-HK,chi,zho,en,eng'),
  en('英文优先', 'en.*', 'en,eng,en-US,en-GB'),
  ja('日文优先', '(ja|en).*', 'ja,jpn,en,eng');

  const SubtitleLanguage(this.label, this.ytDlpLangs, this.mpvLangs);
  final String label;
  /// yt-dlp's `--sub-langs` value; a regex without commas so it fits in
  /// mpv's `ytdl-raw-options` list.
  final String ytDlpLangs;
  /// mpv's `slang`, in order of preference.
  final String mpvLangs;
}

enum VideoSync {
  audio('跟随音频（默认）'),
  displayResample('跟随显示器刷新率（更平滑）');

  const VideoSync(this.label);
  final String label;
  String get mpvValue => this == audio ? 'audio' : 'display-resample';
}

T _enumByName<T extends Enum>(List<T> values, Object? name, T fallback) =>
    values.where((value) => value.name == name).firstOrNull ?? fallback;

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
  final CodecPreference codec;
  final AudioQuality audioQuality;
  /// mpv's `audio-device` name, or `auto` for the Windows default.
  final String audioDevice;
  final VideoSync videoSync;
  /// Highest video height to request, or 0 for no limit.
  final int maxHeight;
  final PlayOrder playOrder;
  final double defaultSpeed;
  final List<double> speeds;
  /// Volume when YTPlus starts, 0–100.
  final int defaultVolume;
  /// Highest volume allowed; above 100 boosts quiet videos.
  final int volumeMax;
  final SubtitleMode subtitleMode;
  final SubtitleLanguage subtitleLanguage;
  final double subtitleBorder;
  final bool subtitleBackground;
  final bool subtitleBold;
  /// Skip segments marked on SponsorBlock. Off by default because it asks a
  /// third-party server, even if only by an anonymous hash prefix.
  final bool sponsorBlock;
  final Set<String> sponsorCategories;
  final bool sponsorNotice;
  final String? cachePath;
  final int? cacheLimitGb;
  final Map<String, String> customOptions;
  final Map<String, DecoderStatus> decoderResults;

  static const defaultSponsorCategories = {'sponsor', 'selfpromo', 'interaction'};

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
    this.codec = CodecPreference.auto,
    this.audioQuality = AudioQuality.best,
    this.audioDevice = 'auto',
    this.videoSync = VideoSync.audio,
    this.maxHeight = 0,
    this.playOrder = PlayOrder.autoPlayRelated,
    this.defaultSpeed = 1.0,
    this.speeds = defaultSpeeds,
    this.defaultVolume = 100,
    this.volumeMax = 100,
    this.subtitleMode = SubtitleMode.off,
    this.subtitleLanguage = SubtitleLanguage.zh,
    this.subtitleBorder = 3,
    this.subtitleBackground = false,
    this.subtitleBold = false,
    this.sponsorBlock = false,
    this.sponsorCategories = defaultSponsorCategories,
    this.sponsorNotice = true,
    this.cachePath,
    this.cacheLimitGb,
    this.customOptions = const {},
    this.decoderResults = const {},
  });

  /// Whether a finished video is followed by another one.
  bool get autoplayNext => playOrder != PlayOrder.pause && playOrder != PlayOrder.singleCycle;

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
    CodecPreference? codec,
    AudioQuality? audioQuality,
    String? audioDevice,
    VideoSync? videoSync,
    int? maxHeight,
    PlayOrder? playOrder,
    double? defaultSpeed,
    List<double>? speeds,
    int? defaultVolume,
    int? volumeMax,
    SubtitleMode? subtitleMode,
    SubtitleLanguage? subtitleLanguage,
    double? subtitleBorder,
    bool? subtitleBackground,
    bool? subtitleBold,
    bool? sponsorBlock,
    Set<String>? sponsorCategories,
    bool? sponsorNotice,
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
        codec: codec ?? this.codec,
        audioQuality: audioQuality ?? this.audioQuality,
        audioDevice: audioDevice ?? this.audioDevice,
        videoSync: videoSync ?? this.videoSync,
        maxHeight: maxHeight ?? this.maxHeight,
        playOrder: playOrder ?? this.playOrder,
        defaultSpeed: defaultSpeed ?? this.defaultSpeed,
        speeds: speeds ?? this.speeds,
        defaultVolume: defaultVolume ?? this.defaultVolume,
        volumeMax: volumeMax ?? this.volumeMax,
        subtitleMode: subtitleMode ?? this.subtitleMode,
        subtitleLanguage: subtitleLanguage ?? this.subtitleLanguage,
        subtitleBorder: subtitleBorder ?? this.subtitleBorder,
        subtitleBackground: subtitleBackground ?? this.subtitleBackground,
        subtitleBold: subtitleBold ?? this.subtitleBold,
        sponsorBlock: sponsorBlock ?? this.sponsorBlock,
        sponsorCategories: sponsorCategories ?? this.sponsorCategories,
        sponsorNotice: sponsorNotice ?? this.sponsorNotice,
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
        'codec': codec.name,
        'audioQuality': audioQuality.name,
        'audioDevice': audioDevice,
        'videoSync': videoSync.name,
        'maxHeight': maxHeight,
        'playOrder': playOrder.name,
        'defaultSpeed': defaultSpeed,
        'speeds': speeds,
        'defaultVolume': defaultVolume,
        'volumeMax': volumeMax,
        'subtitleMode': subtitleMode.name,
        'subtitleLanguage': subtitleLanguage.name,
        'subtitleBorder': subtitleBorder,
        'subtitleBackground': subtitleBackground,
        'subtitleBold': subtitleBold,
        'sponsorBlock': sponsorBlock,
        'sponsorCategories': sponsorCategories.toList(),
        'sponsorNotice': sponsorNotice,
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
    final speeds = raw['speeds'] is List
        ? ((raw['speeds'] as List).whereType<num>().map((s) => s.toDouble()).where((s) => s >= 0.1 && s <= 8).toSet().toList()..sort())
        : defaultSpeeds;
    final categories = raw['sponsorCategories'] is List
        ? (raw['sponsorCategories'] as List).map((c) => c.toString()).where(sponsorCategoryNames.containsKey).toSet()
        : defaultSponsorCategories;
    // Builds before the codec menu had an on/off switch, and before the play
    // order menu an autoplay switch.
    final codec = raw.containsKey('codec')
        ? _enumByName(CodecPreference.values, raw['codec'], CodecPreference.auto)
        : raw['autoSelectCodec'] == false ? CodecPreference.any : CodecPreference.auto;
    final playOrder = raw.containsKey('playOrder')
        ? _enumByName(PlayOrder.values, raw['playOrder'], PlayOrder.autoPlayRelated)
        : raw['autoplayNext'] == false ? PlayOrder.pause : PlayOrder.autoPlayRelated;
    final path = raw['cachePath']?.toString();
    final device = raw['audioDevice']?.toString() ?? 'auto';
    return PlayerSettings(
      hwdec: choice('hwdec', {'auto-safe', 'd3d11va', 'd3d11va-copy', 'dxva2-copy', 'no'}, 'auto-safe'),
      scale: choice('scale', {'spline36', 'bilinear', 'lanczos', 'ewa_lanczossharp'}, 'spline36'),
      deband: raw['deband'] == true,
      interpolation: raw['interpolation'] == true,
      subtitleScale: decimal('subtitleScale', 1.0, 0.5, 3.0),
      subtitlePosition: number('subtitlePosition', 100, 0, 100),
      cacheMode: choice('cacheMode', {'auto', 'yes', 'no'}, 'auto'),
      cacheSeconds: number('cacheSeconds', 30, 1, 600),
      cacheMemoryMb: number('cacheMemoryMb', 64, 16, 1024),
      codec: codec,
      audioQuality: _enumByName(AudioQuality.values, raw['audioQuality'], AudioQuality.best),
      audioDevice: device.isEmpty || device.length > 200 || device.contains(RegExp(r'[\r\n]')) ? 'auto' : device,
      videoSync: _enumByName(VideoSync.values, raw['videoSync'], VideoSync.audio),
      maxHeight: qualityHeights.contains(raw['maxHeight']) ? raw['maxHeight'] as int : 0,
      playOrder: playOrder,
      defaultSpeed: decimal('defaultSpeed', 1.0, 0.1, 8),
      speeds: speeds.isEmpty ? defaultSpeeds : speeds,
      defaultVolume: number('defaultVolume', 100, 0, 100),
      volumeMax: number('volumeMax', 100, 100, 200),
      subtitleMode: _enumByName(SubtitleMode.values, raw['subtitleMode'], SubtitleMode.off),
      subtitleLanguage: _enumByName(SubtitleLanguage.values, raw['subtitleLanguage'], SubtitleLanguage.zh),
      subtitleBorder: decimal('subtitleBorder', 3, 0, 8),
      subtitleBackground: raw['subtitleBackground'] == true,
      subtitleBold: raw['subtitleBold'] == true,
      sponsorBlock: raw['sponsorBlock'] == true,
      sponsorCategories: categories,
      sponsorNotice: raw['sponsorNotice'] != false,
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

/// SponsorBlock's categories with the names PiliNara shows for them.
const sponsorCategoryNames = {
  'sponsor': ('赞助广告', '付费推广、付费推荐和直接广告'),
  'selfpromo': ('自我推广', '无偿推广：周边、捐赠或合作者的信息'),
  'interaction': ('求赞求订阅', '提醒点赞、订阅或关注'),
  'intro': ('片头', '没有实际内容的开场动画、暂停画面'),
  'outro': ('片尾', '结尾致谢、片尾动画和下期预告'),
  'preview': ('回顾与预告', '本集精彩片段或上期回顾'),
  'music_offtopic': ('音乐：非音乐部分', '音乐视频中的非音乐片段'),
  'filler': ('离题闲聊', '与主题无关、只为娱乐的片段'),
};

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
