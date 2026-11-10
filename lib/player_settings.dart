import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Locale, PlatformDispatcher;

import 'app_directories.dart';
import 'decoder_status.dart';
import 'network_proxy.dart';
import 'piped_streams.dart';
import 'translation.dart';
import 'video_codec.dart';
import 'l10n/l10n.dart';

/// Heights offered in the quality menu; 0 means automatic.
const qualityHeights = [0, 2160, 1440, 1080, 720, 480, 360];

/// Speeds offered before the user edits the list, as in PiliNara.
const defaultSpeeds = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 3.0];

/// How playback picks among the codecs that are not disabled; see
/// `FormatPolicy`.
enum PlaybackStrategy {
  auto('Smart auto (recommended)', 'Chosen automatically from hardware decoding support and video quality'),
  quality('Quality first', 'Prefers resolution, frame rate and quality; software decoding allowed'),
  lowResource('Low resource use first', 'Uses hardware decoding wherever possible to lower CPU use');

  const PlaybackStrategy(this._label, this._description);
  final String _label;
  final String _description;
  String get label => tr(_label);
  String get description => tr(_description);
}

enum AudioQuality {
  best('Highest'),
  medium('Medium (≤128 kbps)'),
  low('Data saver (≤64 kbps)');

  const AudioQuality(this._label);
  final String _label;
  String get label => tr(_label);
}

/// What happens when a video ends. Named and ordered like PiliNara's
/// `PlayRepeat`.
enum PlayOrder {
  pause('Pause when finished'),
  listOrder('Play in order'),
  singleCycle('Loop one'),
  listCycle('Loop list'),
  autoPlayRelated('Autoplay next');

  const PlayOrder(this._label);
  final String _label;
  String get label => tr(_label);
}

enum SubtitleMode {
  off("Don't turn on automatically"),
  manual('On when human-made subtitles exist'),
  always('Always on (including auto-generated)');

  const SubtitleMode(this._label);
  final String _label;
  String get label => tr(_label);
}

/// The language the first subtitle is looked for in: one of
/// [TranslationLanguage.all], or [auto] for the interface's.
class SubtitleLanguage {
  const SubtitleLanguage._(this.name, this._code, [this._ytDlpLangs, this._mpvLangs]);

  /// What settings save.
  final String name;
  final String _code;
  final String? _ytDlpLangs;
  final String? _mpvLangs;

  /// The interface's language.
  static const auto = SubtitleLanguage._('auto', '');
  static const zh = SubtitleLanguage._('zh', 'zh-CN', '(zh|en).*', 'zh-Hans,zh-CN,zh-SG,zh,zh-Hant,zh-TW,zh-HK,chi,zho,en,eng');
  static const zhHant = SubtitleLanguage._('zhHant', 'zh-TW', '(zh|en).*', 'zh-Hant,zh-TW,zh-HK,zh,zh-Hans,zh-CN,chi,zho,en,eng');
  static const en = SubtitleLanguage._('en', 'en', 'en.*', 'en,eng,en-US,en-GB');
  static const ja = SubtitleLanguage._('ja', 'ja', '(ja|en).*', 'ja,jpn,en,eng');
  static const ko = SubtitleLanguage._('ko', 'ko', '(ko|en).*', 'ko,kor,en,eng');
  static const fr = SubtitleLanguage._('fr', 'fr', '(fr|en).*', 'fr,fre,fra,en,eng');
  static const de = SubtitleLanguage._('de', 'de', '(de|en).*', 'de,ger,deu,en,eng');
  static const es = SubtitleLanguage._('es', 'es', '(es|en).*', 'es,spa,en,eng');
  static const pt = SubtitleLanguage._('pt', 'pt', '(pt|en).*', 'pt,pt-BR,por,en,eng');
  static const ru = SubtitleLanguage._('ru', 'ru', '(ru|en).*', 'ru,rus,en,eng');
  static const it = SubtitleLanguage._('it', 'it', '(it|en).*', 'it,ita,en,eng');
  static const vi = SubtitleLanguage._('vi', 'vi', '(vi|en).*', 'vi,vie,en,eng');
  static const th = SubtitleLanguage._('th', 'th', '(th|en).*', 'th,tha,en,eng');
  static const id = SubtitleLanguage._('id', 'id', '(id|en).*', 'id,ind,en,eng');
  static const ar = SubtitleLanguage._('ar', 'ar', '(ar|en).*', 'ar,ara,en,eng');
  static const hi = SubtitleLanguage._('hi', 'hi', '(hi|en).*', 'hi,hin,en,eng');

  static const _named = [auto, zh, zhHant, en, ja, ko, fr, de, es, pt, ru, it, vi, th, id, ar, hi];

  /// Every choice: [auto], then each translation language.
  static final List<SubtitleLanguage> values = [
    ..._named,
    for (final l in TranslationLanguage.all)
      if (!_named.any((n) => n._code == l.code)) SubtitleLanguage._(l.code, l.code),
  ];

  /// The choice saved as [name]; null for an unknown one.
  static SubtitleLanguage? byName(Object? name) => values.where((l) => l.name == name).firstOrNull;

  String get label => this == auto ? tr('Interface language ({0})', [resolved.label]) : translation.label;

  /// yt-dlp's `--sub-langs` value; a regex without commas so it fits in
  /// mpv's `ytdl-raw-options` list.
  String get ytDlpLangs {
    final l = resolved;
    return l._ytDlpLangs ?? '(${[...l.translation.tags, 'en'].join('|')}).*';
  }

  /// mpv's `slang`, in order of preference.
  String get mpvLangs {
    final l = resolved;
    return l._mpvLangs ?? [...l.translation.tags, 'en', 'eng'].join(',');
  }

  /// Windows' language; tests replace it.
  static Locale Function() systemLocale = () => PlatformDispatcher.instance.locale;

  /// Windows' language as a translation language, English when there is
  /// none for it.
  static TranslationLanguage get systemTranslation => switch (systemLocale()) {
        Locale(languageCode: 'zh', scriptCode: 'Hant') || Locale(languageCode: 'zh', countryCode: 'TW' || 'HK' || 'MO') => TranslationLanguage.byCode('zh-TW'),
        Locale(:final languageCode) => TranslationLanguage.ofTag(languageCode) ?? TranslationLanguage.byCode('en'),
      };

  /// The language subtitles are translated into when a video has none in
  /// this one.
  TranslationLanguage get translation => this == auto ? interfaceTranslationLanguage : TranslationLanguage.byCode(_code);

  /// [auto] as the language it stands for.
  SubtitleLanguage get resolved {
    if (this != auto) return this;
    final code = interfaceTranslationLanguage.code;
    return values.where((l) => l != auto && l._code == code).firstOrNull ?? en;
  }

  @override
  bool operator ==(Object other) => other is SubtitleLanguage && other.name == name;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => name;
}

/// mpv's `--video-sync` modes, as PiliNara lists them.
enum VideoSync {
  audio('audio', 'Sync to audio (default)'),
  displayResample('display-resample', 'Resample to display refresh rate (smoother)'),
  displayResampleVdrop('display-resample-vdrop', 'Resample, drop frames if needed'),
  displayResampleDesync('display-resample-desync', "Resample, don't sync audio"),
  displayTempo('display-tempo', 'Resample audio to display refresh rate'),
  displayVdrop('display-vdrop', 'Sync to display, drop or repeat video frames'),
  displayAdrop('display-adrop', 'Sync to display, drop or repeat audio'),
  displayDesync('display-desync', "Sync to display, don't sync audio"),
  desync('desync', "Don't sync (debug only)");

  const VideoSync(this._mpvValue, this._label);
  final String _mpvValue;
  String get mpvValue => tr(_mpvValue);
  final String _label;
  String get label => tr(_label);
}

/// mpv's `--hwdec` decoders that exist on this system, from PiliNara's
/// `HwDecType`. The setting is an ordered list; mpv tries them in turn.
/// Decoders without "-copy" hand frames to the renderer in GPU memory (zero
/// copy); "-copy" ones copy them back to system memory first.
List<(String, String)> get hwdecChoices => Platform.isWindows
    ? _windowsHwdec
    : Platform.isMacOS
        ? _macHwdec
        : _linuxHwdec;

final _macHwdec = <(String, String)>[
  ('no', tr('Software decoding')),
  ('auto', tr('Any available hardware decoder')),
  ('auto-safe', tr('Best stable hardware decoder (default)')),
  ('auto-copy', tr('Best hardware decoder with copy-back')),
  ('videotoolbox', tr('VideoToolbox (zero-copy)')),
  ('videotoolbox-copy', tr('VideoToolbox (copy-back)')),
];

final _linuxHwdec = <(String, String)>[
  ('no', tr('Software decoding')),
  ('auto', tr('Any available hardware decoder')),
  ('auto-safe', tr('Best stable hardware decoder (default)')),
  ('auto-copy', tr('Best hardware decoder with copy-back')),
  ('vaapi', tr('VA-API (Intel, AMD, zero-copy)')),
  ('vaapi-copy', tr('VA-API (copy-back)')),
  ('nvdec', tr('NVDEC (NVIDIA only, zero-copy)')),
  ('nvdec-copy', tr('NVDEC (NVIDIA only, copy-back)')),
  ('vulkan', tr('Vulkan (experimental, zero-copy)')),
  ('vulkan-copy', tr('Vulkan (experimental, copy-back)')),
  ('cuda', tr('CUDA (NVIDIA only, legacy, zero-copy)')),
  ('cuda-copy', tr('CUDA (NVIDIA only, legacy, copy-back)')),
];

final _windowsHwdec = <(String, String)>[
  ('no', tr('Software decoding')),
  ('auto', tr('Any available hardware decoder')),
  ('auto-safe', tr('Best stable hardware decoder (default)')),
  ('auto-copy', tr('Best hardware decoder with copy-back')),
  ('d3d12va', tr('DirectX 12 (Windows 10 and later, zero-copy)')),
  ('d3d12va-copy', tr('DirectX 12 (copy-back)')),
  ('d3d11va', tr('DirectX 11 (Windows 8 and later, zero-copy)')),
  ('d3d11va-copy', tr('DirectX 11 (copy-back)')),
  ('dxva2', tr('DXVA2 (Windows 7 and later, zero-copy)')),
  ('dxva2-copy', tr('DXVA2 (copy-back)')),
  ('nvdec', tr('NVDEC (NVIDIA only, zero-copy)')),
  ('nvdec-copy', tr('NVDEC (NVIDIA only, copy-back)')),
  ('vulkan', tr('Vulkan (experimental, zero-copy)')),
  ('vulkan-copy', tr('Vulkan (experimental, copy-back)')),
  ('cuda', tr('CUDA (NVIDIA only, legacy, zero-copy)')),
  ('cuda-copy', tr('CUDA (NVIDIA only, legacy, copy-back)')),
  ('amf', tr('AMF (AMD only, zero-copy)')),
  ('amf-copy', tr('AMF (AMD only, copy-back)')),
  ('qsv', tr('Quick Sync Video (Intel only, zero-copy)')),
  ('qsv-copy', tr('Quick Sync Video (Intel only, copy-back)')),
];

/// The codecs libmpv tries hardware decoding for: YouTube's own and the
/// common ones of downloaded or local files. Which of YouTube's codecs play
/// at all is up to the disabled codecs.
const defaultHwdecCodecs = 'h264,vc1,hevc,vp8,vp9,av1,prores,ffv1';

/// PiliNara's 音量均衡 presets, as mpv `--af` filters.
List<(String, String)> get audioFilterPresets => [
  ('', tr('Close')),
  ('dynaudnorm=g=5:f=250:r=0.9:p=0.5', tr('Preset dynaudnorm (dynamic normalization)')),
  ('loudnorm=I=-16:LRA=11:TP=-1.5', tr('Preset loudnorm (loudness normalization)')),
];

/// Picture adjustments PiliNara offers in its player, as mpv properties.
/// How far each picture property may go either way. Brightness stops short
/// of mpv's ±100, which turns the picture all black or all white.
int pictureLimit(String key) => key == 'brightness' ? 50 : 100;

List<(String, String)> get pictureProperties => [
      ('brightness', tr('Brightness')),
      ('contrast', tr('Contrast')),
      ('saturation', tr('Saturation')),
      ('gamma', tr('Gamma')),
      ('hue', tr('Hue')),
    ];

/// Options a custom line may not set: ones that load code or files, write
/// files, or would break media_kit's rendering and playback control.
const _blockedOptions = {
  'vo', 'wid', 'include', 'config', 'config-dir', 'ytdl', 'ytdl-path', 'idle', 'keep-open', 'force-window',
  'log-file', 'o', 'of', 'ofopts', 'ovc', 'ovcopts', 'oac', 'oacopts', 'stream-record', 'record-file',
  'input-conf', 'use-filedir-conf', 'watch-later-dir', 'watch-later-directory', 'screenshot-directory', 'screenshot-dir',
};
const _blockedPrefixes = ['script', 'load-', 'input-ipc', 'dump-', 'glsl-shader', 'lua'];

/// One line of a custom mpv.conf that was not applied, and why.
typedef RejectedOption = (String line, String reason);

/// Reads mpv.conf syntax: `key=value`, `key = value`, `--key=value`, a bare
/// `key` for yes and `no-key` for no, with `#` comments.
(Map<String, String>, List<RejectedOption>) parseMpvConf(String text) {
  final options = <String, String>{};
  final rejected = <RejectedOption>[];
  for (final raw in const LineSplitter().convert(text)) {
    var line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final comment = line.indexOf(RegExp(r'\s#'));
    if (comment >= 0) line = line.substring(0, comment).trim();
    if (line.startsWith('[')) {
      rejected.add((raw.trim(), tr("Profiles aren't supported")));
      continue;
    }
    if (line.startsWith('--')) line = line.substring(2);
    final eq = line.indexOf('=');
    var key = (eq < 0 ? line : line.substring(0, eq)).trim().toLowerCase();
    var value = eq < 0 ? 'yes' : line.substring(eq + 1).trim();
    if (eq < 0 && key.startsWith('no-') && key.length > 3) {
      key = key.substring(3);
      value = 'no';
    }
    if (value.length >= 2 && ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'")))) {
      value = value.substring(1, value.length - 1);
    }
    final reason = PlayerSettings.customOptionProblem(key, value);
    if (reason == null) {
      options[key] = value;
    } else {
      rejected.add((raw.trim(), reason));
    }
  }
  return (options, rejected);
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
  /// The main subtitle's font family (empty: the default), color
  /// (0xRRGGBB) and opacity (0.1 to 1); [subtitleScale] is its size.
  final String subtitleFont;
  final int subtitleColor;
  final double subtitleOpacity;
  /// The same for the secondary subtitle (双语字幕), drawn above the main.
  /// libmpv has no separate style for it, so these apply only while the
  /// interface draws subtitles.
  final String secondaryFont;
  final double secondaryScale;
  final int secondaryColor;
  final double secondaryOpacity;
  final String cacheMode;
  final int cacheSeconds;
  final int cacheMemoryMb;
  final PlaybackStrategy strategy;
  /// The codecs the user chose to disable; null leaves them to Lumtub.
  final Set<VideoCodec>? chosenCodecs;

  /// Codecs no strategy may pick, whatever the video offers: the user's
  /// choice, or else [automaticCodecs].
  Set<VideoCodec> get disabledCodecs => chosenCodecs ?? automaticCodecs;

  /// The codecs disabled for the user: VP9 and AV1 unless this PC decodes
  /// them in hardware, so playback stays light. Above 1080p, which H.264
  /// cannot reach, VP9 stays enabled even in software.
  Set<VideoCodec> get automaticCodecs {
    bool hardware(String key) => hwdec != 'no' && (decoderResults[key]?.isHardware ?? false);
    final off = {if (!hardware('av1')) VideoCodec.av1, if (!hardware('vp9')) VideoCodec.vp9};
    if (maxHeight > 1080 && off.length == 2) off.remove(VideoCodec.vp9);
    return off;
  }

  /// Whether the user chose the codecs rather than Lumtub.
  bool get codecsChosen => chosenCodecs != null;

  /// These settings with [disabled] disabled: the user's choice, or back to
  /// the automatic one when it is the same.
  PlayerSettings withDisabledCodecs(Set<VideoCodec> disabled) =>
      _sameCodecs(disabled, copyWith(automaticCodecs: true).automaticCodecs) ? copyWith(automaticCodecs: true) : copyWith(disabledCodecs: disabled);

  static bool _sameCodecs(Set<VideoCodec> a, Set<VideoCodec> b) => a.length == b.length && a.containsAll(b);
  final AudioQuality audioQuality;
  /// mpv's `audio-device` name, or `auto` for the Windows default.
  final String audioDevice;
  final VideoSync videoSync;
  /// Highest video height to request, or 0 for no limit.
  final int maxHeight;
  final PlayOrder playOrder;
  final double defaultSpeed;
  final List<double> speeds;
  /// Volume when Lumtub starts, 0–100.
  final int defaultVolume;
  /// Highest volume allowed; above 100 boosts quiet videos.
  final int volumeMax;
  final SubtitleMode subtitleMode;
  final SubtitleLanguage subtitleLanguage;
  /// The first subtitle in the language the video is spoken in rather than
  /// [subtitleLanguage].
  final bool subtitleOriginal;
  /// The TranslationLanguage code of the subtitle shown above the main
  /// one when a video opens; empty for none.
  /// [secondarySubtitleLanguage] for the video's own subtitle in its own
  /// language, uploaded or automatic.
  static const originalSubtitle = 'original';
  /// [secondarySubtitleLanguage] for the interface's language, the default.
  static const interfaceSubtitle = 'interface';
  final String secondarySubtitleLanguage;

  /// The language [secondarySubtitleLanguage] names, null for none or the
  /// video's own.
  TranslationLanguage? get secondaryTarget =>
      secondarySubtitleLanguage == interfaceSubtitle ? interfaceTranslationLanguage : TranslationLanguage.maybeByCode(secondarySubtitleLanguage);
  final double subtitleBorder;
  final bool subtitleBackground;
  final bool subtitleBold;
  /// Skip segments marked on SponsorBlock. Off by default because it asks a
  /// third-party server, even if only by an anonymous hash prefix.
  final bool sponsorBlock;
  /// Shows Return YouTube Dislike's estimate of the dislikes.
  final bool returnDislike;
  /// The graphics adapter and driver [decoderResults] were measured on.
  final String decoderAdapter;
  /// DeArrow's titles and thumbnails in place of YouTube's.
  final bool deArrowTitles;
  final bool deArrowThumbnails;
  final Set<String> sponsorCategories;
  final bool sponsorNotice;
  /// Leave the chosen segments out of downloaded files, at keyframes.
  final bool sponsorCut;
  final String? cachePath;
  final int? cacheLimitGb;
  /// Extra libmpv options in mpv.conf syntax, applied after all others.
  final String mpvConf;
  final Map<String, DecoderStatus> decoderResults;
  /// `--d3d11va-zero-copy`.
  final bool d3d11vaZeroCopy;
  /// libmpv draws subtitles itself (libass), so the mpv subtitle options
  /// apply; off, Flutter draws them over the video. Takes effect on restart.
  final bool libassSubtitles;
  /// How yt-dlp, libmpv and the app reach YouTube.
  final ProxyMode proxyMode;
  /// The proxy for [ProxyMode.custom], such as `127.0.0.1:7890`.
  final String proxyAddress;
  /// 加密 DNS: a [DnsServer] id, `custom` for [dnsCustomUrl], or `''` for
  /// the system resolver.
  final String dnsServer;
  final String dnsCustomUrl;
  /// The certificate authorities the app's HTTPS trusts: `system` (the
  /// system's store), `mozilla` or `google`.
  final String certificateRoots;
  /// Where playback streams come from: YouTube directly by default.
  final PlaybackSource playbackSource;
  /// The Piped API server for [PlaybackSource.pipedCustom].
  final String pipedServer;
  /// The Invidious instance for [PlaybackSource.invidiousCustom].
  final String invidiousServer;
  /// `--vd-lavc-dr`: auto, yes or no.
  final String directRendering;
  /// `--autosync`; 0 turns it off.
  final int autosync;
  /// `--af`, such as a loudness filter; empty for none.
  final String audioFilter;
  /// Brightness, contrast, saturation, gamma and hue, -100 to 100.
  final Map<String, int> picture;
  final int audioDelayMs;

  /// The usable lines of [mpvConf].
  Map<String, String> get customOptions => parseMpvConf(mpvConf).$1;

  static const defaultSponsorCategories = {'sponsor', 'selfpromo', 'interaction'};

  const PlayerSettings({
    this.hwdec = 'auto-safe',
    this.scale = 'spline36',
    this.deband = false,
    this.interpolation = false,
    this.subtitleScale = 1.0,
    this.subtitlePosition = 100,
    this.subtitleFont = defaultSubtitleFont,
    this.subtitleColor = 0xFFFFFF,
    this.subtitleOpacity = 1.0,
    this.secondaryFont = defaultSubtitleFont,
    this.secondaryScale = 0.9,
    this.secondaryColor = 0xFFE7A8,
    this.secondaryOpacity = 0.95,
    this.cacheMode = 'auto',
    this.cacheSeconds = 60,
    this.cacheMemoryMb = 150,
    this.strategy = PlaybackStrategy.auto,
    Set<VideoCodec>? disabledCodecs,
    this.audioQuality = AudioQuality.best,
    this.audioDevice = 'auto',
    this.videoSync = VideoSync.audio,
    this.maxHeight = 0,
    this.playOrder = PlayOrder.pause,
    this.defaultSpeed = 1.0,
    this.speeds = defaultSpeeds,
    this.defaultVolume = 100,
    this.volumeMax = 100,
    this.subtitleMode = SubtitleMode.off,
    this.subtitleLanguage = SubtitleLanguage.auto,
    this.subtitleOriginal = false,
    this.secondarySubtitleLanguage = interfaceSubtitle,
    this.subtitleBorder = 3,
    this.subtitleBackground = false,
    this.subtitleBold = false,
    this.sponsorBlock = false,
    this.returnDislike = false,
    this.decoderAdapter = '',
    this.deArrowTitles = false,
    this.deArrowThumbnails = false,
    this.sponsorCategories = defaultSponsorCategories,
    this.sponsorNotice = true,
    this.sponsorCut = false,
    this.cachePath,
    this.cacheLimitGb,
    this.mpvConf = '',
    this.decoderResults = const {},
    this.d3d11vaZeroCopy = false,
    this.libassSubtitles = false,
    this.proxyMode = ProxyMode.system,
    this.proxyAddress = '',
    this.dnsServer = '',
    this.dnsCustomUrl = '',
    this.certificateRoots = 'system',
    this.playbackSource = PlaybackSource.youtube,
    this.pipedServer = '',
    this.invidiousServer = '',
    this.directRendering = 'auto',
    this.autosync = 0,
    this.audioFilter = '',
    this.picture = const {},
    this.audioDelayMs = 0,
  }) : chosenCodecs = disabledCodecs;

  /// Whether a finished video is followed by another one.
  bool get autoplayNext => playOrder != PlayOrder.pause && playOrder != PlayOrder.singleCycle;

  PlayerSettings copyWith({
    String? hwdec,
    String? scale,
    bool? deband,
    bool? interpolation,
    double? subtitleScale,
    int? subtitlePosition,
    String? subtitleFont,
    int? subtitleColor,
    double? subtitleOpacity,
    String? secondaryFont,
    double? secondaryScale,
    int? secondaryColor,
    double? secondaryOpacity,
    String? cacheMode,
    int? cacheSeconds,
    int? cacheMemoryMb,
    PlaybackStrategy? strategy,
    Set<VideoCodec>? disabledCodecs,
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
    bool? subtitleOriginal,
    String? secondarySubtitleLanguage,
    double? subtitleBorder,
    bool? subtitleBackground,
    bool? subtitleBold,
    bool? sponsorBlock,
    bool? returnDislike,
    bool automaticCodecs = false,
    String? decoderAdapter,
    bool? deArrowTitles,
    bool? deArrowThumbnails,
    Set<String>? sponsorCategories,
    bool? sponsorNotice,
    bool? sponsorCut,
    String? cachePath,
    bool clearCachePath = false,
    int? cacheLimitGb,
    bool clearCacheLimit = false,
    String? mpvConf,
    Map<String, DecoderStatus>? decoderResults,
    bool? d3d11vaZeroCopy,
    bool? libassSubtitles,
    ProxyMode? proxyMode,
    String? proxyAddress,
    String? dnsServer,
    String? dnsCustomUrl,
    String? certificateRoots,
    PlaybackSource? playbackSource,
    String? pipedServer,
    String? invidiousServer,
    String? directRendering,
    int? autosync,
    String? audioFilter,
    Map<String, int>? picture,
    int? audioDelayMs,
  }) => PlayerSettings(
        hwdec: hwdec ?? this.hwdec,
        scale: scale ?? this.scale,
        deband: deband ?? this.deband,
        interpolation: interpolation ?? this.interpolation,
        subtitleScale: subtitleScale ?? this.subtitleScale,
        subtitlePosition: subtitlePosition ?? this.subtitlePosition,
        subtitleFont: subtitleFont ?? this.subtitleFont,
        subtitleColor: subtitleColor ?? this.subtitleColor,
        subtitleOpacity: subtitleOpacity ?? this.subtitleOpacity,
        secondaryFont: secondaryFont ?? this.secondaryFont,
        secondaryScale: secondaryScale ?? this.secondaryScale,
        secondaryColor: secondaryColor ?? this.secondaryColor,
        secondaryOpacity: secondaryOpacity ?? this.secondaryOpacity,
        cacheMode: cacheMode ?? this.cacheMode,
        cacheSeconds: cacheSeconds ?? this.cacheSeconds,
        cacheMemoryMb: cacheMemoryMb ?? this.cacheMemoryMb,
        strategy: strategy ?? this.strategy,
        disabledCodecs: automaticCodecs ? null : disabledCodecs ?? chosenCodecs,
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
        subtitleOriginal: subtitleOriginal ?? this.subtitleOriginal,
        secondarySubtitleLanguage: secondarySubtitleLanguage ?? this.secondarySubtitleLanguage,
        subtitleBorder: subtitleBorder ?? this.subtitleBorder,
        subtitleBackground: subtitleBackground ?? this.subtitleBackground,
        subtitleBold: subtitleBold ?? this.subtitleBold,
        sponsorBlock: sponsorBlock ?? this.sponsorBlock,
        returnDislike: returnDislike ?? this.returnDislike,
        decoderAdapter: decoderAdapter ?? this.decoderAdapter,
        deArrowTitles: deArrowTitles ?? this.deArrowTitles,
        deArrowThumbnails: deArrowThumbnails ?? this.deArrowThumbnails,
        sponsorCategories: sponsorCategories ?? this.sponsorCategories,
        sponsorNotice: sponsorNotice ?? this.sponsorNotice,
        sponsorCut: sponsorCut ?? this.sponsorCut,
        cachePath: clearCachePath ? null : cachePath ?? this.cachePath,
        cacheLimitGb: clearCacheLimit ? null : cacheLimitGb ?? this.cacheLimitGb,
        mpvConf: mpvConf ?? this.mpvConf,
        decoderResults: decoderResults ?? this.decoderResults,
        d3d11vaZeroCopy: d3d11vaZeroCopy ?? this.d3d11vaZeroCopy,
        libassSubtitles: libassSubtitles ?? this.libassSubtitles,
        proxyMode: proxyMode ?? this.proxyMode,
        proxyAddress: proxyAddress ?? this.proxyAddress,
        dnsServer: dnsServer ?? this.dnsServer,
        dnsCustomUrl: dnsCustomUrl ?? this.dnsCustomUrl,
        certificateRoots: certificateRoots ?? this.certificateRoots,
        playbackSource: playbackSource ?? this.playbackSource,
        pipedServer: pipedServer ?? this.pipedServer,
        invidiousServer: invidiousServer ?? this.invidiousServer,
        directRendering: directRendering ?? this.directRendering,
        autosync: autosync ?? this.autosync,
        audioFilter: audioFilter ?? this.audioFilter,
        picture: picture ?? this.picture,
        audioDelayMs: audioDelayMs ?? this.audioDelayMs,
      );

  Map<String, dynamic> toJson() => {
        'hwdec': hwdec,
        'scale': scale,
        'deband': deband,
        'interpolation': interpolation,
        'subtitleScale': subtitleScale,
        'subtitlePosition': subtitlePosition,
        'subtitleFont': subtitleFont,
        'subtitleColor': subtitleColor,
        'subtitleOpacity': subtitleOpacity,
        'secondaryFont': secondaryFont,
        'secondaryScale': secondaryScale,
        'secondaryColor': secondaryColor,
        'secondaryOpacity': secondaryOpacity,
        'cacheMode': cacheMode,
        'cacheSeconds': cacheSeconds,
        'cacheMemoryMb': cacheMemoryMb,
        'bufferDefaults': 2,
        'subtitleStyleVersion': 2,
        'strategy': strategy.name,
        'disabledCodecs': chosenCodecs == null ? null : [for (final c in VideoCodec.values) if (chosenCodecs!.contains(c)) c.name],
        'audioQuality': audioQuality.name,
        'audioDevice': audioDevice,
        'videoSync': videoSync.name,
        'maxHeight': maxHeight,
        'playOrder': playOrder.name,
        'playOrderDefault': 2,
        'defaultSpeed': defaultSpeed,
        'speeds': speeds,
        'defaultVolume': defaultVolume,
        'volumeMax': volumeMax,
        'subtitleMode': subtitleMode.name,
        'subtitleLanguageV2': subtitleLanguage.name,
        'subtitleOriginal': subtitleOriginal,
        'secondarySubtitleLanguageV2': secondarySubtitleLanguage,
        'subtitleBorder': subtitleBorder,
        'subtitleBackground': subtitleBackground,
        'subtitleBold': subtitleBold,
        'sponsorBlock': sponsorBlock,
        'returnDislike': returnDislike,
        'decoderAdapter': decoderAdapter,
        'deArrowTitles': deArrowTitles,
        'deArrowThumbnails': deArrowThumbnails,
        'sponsorCategories': sponsorCategories.toList(),
        'sponsorNotice': sponsorNotice,
        'sponsorCut': sponsorCut,
        if (cachePath != null) 'cachePath': cachePath,
        if (cacheLimitGb != null) 'cacheLimitGb': cacheLimitGb,
        'mpvConf': mpvConf,
        'd3d11vaZeroCopy': d3d11vaZeroCopy,
        'libassSubtitles': libassSubtitles,
        'proxyMode': proxyMode.name,
        'proxyAddress': proxyAddress,
        'dnsServer': dnsServer,
        'dnsCustomUrl': dnsCustomUrl,
        'certificateRoots': certificateRoots,
        'playbackSourceV2': playbackSource.name,
        'pipedServer': pipedServer,
        'invidiousServer': invidiousServer,
        'directRendering': directRendering,
        'autosync': autosync,
        'audioFilter': audioFilter,
        'picture': picture,
        'audioDelayMs': audioDelayMs,
        'decoderResults': decoderResults.map((codec, status) => MapEntry(codec, status.toJson())),
      };

  /// Microsoft YaHei: on every Windows, with Chinese and Latin letters
  /// that read well over video.
  static const defaultSubtitleFont = 'Microsoft YaHei';

  /// [font] as libass should ask for it here: the default Windows font
  /// becomes the system's own Chinese font on macOS and Linux.
  static String fontForThisSystem(String font) {
    if (font != defaultSubtitleFont || Platform.isWindows) return font;
    return Platform.isMacOS ? 'PingFang SC' : 'Noto Sans CJK SC';
  }

  /// These settings with the subtitle style of a fresh install.
  PlayerSettings withDefaultSubtitleStyle() {
    const d = PlayerSettings();
    return copyWith(
      subtitleScale: d.subtitleScale,
      subtitlePosition: d.subtitlePosition,
      subtitleFont: d.subtitleFont,
      subtitleColor: d.subtitleColor,
      subtitleOpacity: d.subtitleOpacity,
      secondaryFont: d.secondaryFont,
      secondaryScale: d.secondaryScale,
      secondaryColor: d.secondaryColor,
      secondaryOpacity: d.secondaryOpacity,
      subtitleBorder: d.subtitleBorder,
      subtitleBackground: d.subtitleBackground,
      subtitleBold: d.subtitleBold,
    );
  }

  /// [value] as a font family name, or empty when it is none: the name
  /// goes into mpv's options as it is.
  static String cleanFont(Object? value) {
    final name = value is String ? value.trim() : '';
    return name.length > 64 || name.contains(RegExp(r'[\x00-\x1f,;"]')) ? '' : name;
  }

  /// [rgb] (0xRRGGBB) at [opacity] as mpv's #AARRGGBB.
  static String mpvColor(int rgb, double opacity) =>
      '#${(opacity.clamp(0, 1) * 255).round().toRadixString(16).padLeft(2, '0')}${(rgb & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}'.toUpperCase();

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
    final results = <String, DecoderStatus>{};
    // Earlier builds kept custom options as a map.
    var conf = raw['mpvConf'] is String ? raw['mpvConf'] as String : '';
    if (conf.isEmpty && raw['customOptions'] is Map) {
      conf = [for (final entry in (raw['customOptions'] as Map).entries) '${entry.key}=${entry.value}'].join('\n');
    }
    if (conf.length > 200000) conf = '';
    final picture = <String, int>{};
    if (raw['picture'] is Map) {
      for (final (key, _) in pictureProperties) {
        final value = (raw['picture'] as Map)[key];
        if (value is num && value != 0) picture[key] = value.toInt().clamp(-pictureLimit(key), pictureLimit(key));
      }
    }
    final filter = raw['audioFilter']?.toString() ?? '';
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
    // Builds before the format policy saved a preferred `codec`: "any" and a
    // switched-off codec selection meant best quality, the rest automatic.
    final strategy = raw.containsKey('strategy')
        ? _enumByName(PlaybackStrategy.values, raw['strategy'], PlaybackStrategy.auto)
        : raw['codec'] == 'any' || raw['autoSelectCodec'] == false ? PlaybackStrategy.quality : PlaybackStrategy.auto;
    final disabled = raw['disabledCodecs'] is List
        ? {for (final name in raw['disabledCodecs'] as List) VideoCodec.byName(name)}.whereType<VideoCodec>().toSet()
        : null;
    // A file that disables every codec YouTube plays would play nothing.
    if (disabled != null && !VideoCodec.playableWithout(disabled)) disabled.remove(VideoCodec.h264);
    // Builds before the play order menu had an autoplay switch.
    // Builds before playOrderDefault 2 saved 自动连播 as the default even
    // when untouched; the default is now to stop at the end.
    final savedOrder = raw.containsKey('playOrder')
        ? _enumByName(PlayOrder.values, raw['playOrder'], PlayOrder.pause)
        : raw['autoplayNext'] == false ? PlayOrder.pause : PlayOrder.autoPlayRelated;
    final playOrder = raw['playOrderDefault'] != 2 && savedOrder == PlayOrder.autoPlayRelated ? PlayOrder.pause : savedOrder;
    final path = raw['cachePath']?.toString();
    final device = raw['audioDevice']?.toString() ?? 'auto';
    final oldBuffer = raw['bufferDefaults'] != 2;
    final loaded = PlayerSettings(
      hwdec: validHwdec(raw['hwdec']?.toString()) ?? 'auto-safe',
      scale: choice('scale', {'spline36', 'bilinear', 'lanczos', 'ewa_lanczossharp'}, 'spline36'),
      deband: raw['deband'] == true,
      interpolation: raw['interpolation'] == true,
      subtitleScale: decimal('subtitleScale', 1.0, 0.5, 3.0),
      subtitlePosition: number('subtitlePosition', 100, 0, 100),
      subtitleFont: raw.containsKey('subtitleFont') ? cleanFont(raw['subtitleFont']) : defaultSubtitleFont,
      subtitleColor: number('subtitleColor', 0xFFFFFF, 0, 0xFFFFFF),
      subtitleOpacity: decimal('subtitleOpacity', 1.0, 0.1, 1.0),
      secondaryFont: raw.containsKey('secondaryFont') ? cleanFont(raw['secondaryFont']) : defaultSubtitleFont,
      // 0.8 was the default before it grew to 0.9, too small to read;
      // from subtitleStyleVersion 2 on, a saved 0.8 was chosen.
      secondaryScale: raw['secondaryScale'] == 0.8 && raw['subtitleStyleVersion'] != 2 ? 0.9 : decimal('secondaryScale', 0.9, 0.5, 3.0),
      secondaryColor: number('secondaryColor', 0xFFE7A8, 0, 0xFFFFFF),
      secondaryOpacity: decimal('secondaryOpacity', 0.95, 0.1, 1.0),
      cacheMode: choice('cacheMode', {'auto', 'yes', 'no'}, 'auto'),
      // Builds before bufferDefaults 2 saved 30 s / 64 MB even when untouched;
      // those move to the larger defaults that ride out network hiccups.
      cacheSeconds: oldBuffer && raw['cacheSeconds'] == 30 ? 60 : number('cacheSeconds', 60, 1, 600),
      cacheMemoryMb: oldBuffer && raw['cacheMemoryMb'] == 64 ? 150 : number('cacheMemoryMb', 150, 16, 1024),
      strategy: strategy,
      disabledCodecs: disabled,
      audioQuality: _enumByName(AudioQuality.values, raw['audioQuality'], AudioQuality.best),
      audioDevice: device.isEmpty || device.length > 200 || device.contains(RegExp(r'[\r\n]')) ? 'auto' : device,
      videoSync: _enumByName(VideoSync.values, raw['videoSync'], VideoSync.audio),
      maxHeight: raw['maxHeight'] is int && (raw['maxHeight'] as int) >= 0 && (raw['maxHeight'] as int) <= 4320 ? raw['maxHeight'] as int : 0,
      playOrder: playOrder,
      defaultSpeed: decimal('defaultSpeed', 1.0, 0.1, 8),
      speeds: speeds.isEmpty ? defaultSpeeds : speeds,
      defaultVolume: number('defaultVolume', 100, 0, 100),
      volumeMax: number('volumeMax', 100, 100, 200),
      subtitleMode: _enumByName(SubtitleMode.values, raw['subtitleMode'], SubtitleMode.off),
      // Saved under a new key since 跟随界面语言 came; 简体中文优先, the
      // default before it, saved under the old one now follows too.
      subtitleLanguage: raw.containsKey('subtitleLanguageV2') || raw['subtitleLanguage'] != 'zh'
          ? SubtitleLanguage.byName(raw['subtitleLanguageV2'] ?? raw['subtitleLanguage']) ?? SubtitleLanguage.auto
          : SubtitleLanguage.auto,
      subtitleOriginal: raw['subtitleOriginal'] == true,
      // Saved under a new key since the interface's language became the
      // default; none, the default before it, follows it too.
      secondarySubtitleLanguage: switch (raw['secondarySubtitleLanguageV2'] ?? (raw['secondarySubtitleLanguage'] == '' ? null : raw['secondarySubtitleLanguage'])) {
        null => interfaceSubtitle,
        originalSubtitle => originalSubtitle,
        interfaceSubtitle => interfaceSubtitle,
        final saved => TranslationLanguage.maybeByCode(saved)?.code ?? '',
      },
      subtitleBorder: decimal('subtitleBorder', 3, 0, 8),
      subtitleBackground: raw['subtitleBackground'] == true,
      subtitleBold: raw['subtitleBold'] == true,
      sponsorBlock: raw['sponsorBlock'] == true,
      returnDislike: raw['returnDislike'] == true,
      decoderAdapter: raw['decoderAdapter']?.toString() ?? '',
      deArrowTitles: raw['deArrowTitles'] == true,
      deArrowThumbnails: raw['deArrowThumbnails'] == true,
      sponsorCategories: categories,
      sponsorNotice: raw['sponsorNotice'] != false,
      sponsorCut: raw['sponsorCut'] == true,
      cachePath: path != null && path.trim().isNotEmpty ? path : null,
      cacheLimitGb: raw['cacheLimitGb'] == null ? null : number('cacheLimitGb', 1, 1, 100),
      mpvConf: conf,
      decoderResults: results,
      d3d11vaZeroCopy: raw['d3d11vaZeroCopy'] == true,
      libassSubtitles: raw['libassSubtitles'] == true,
      proxyMode: _enumByName(ProxyMode.values, raw['proxyMode'], ProxyMode.system),
      proxyAddress: NetworkProxy.normalize(raw['proxyAddress']?.toString() ?? '') ?? '',
      dnsServer: raw['dnsServer']?.toString() ?? '',
      dnsCustomUrl: raw['dnsCustomUrl']?.toString() ?? '',
      certificateRoots: const ['mozilla', 'google'].contains(raw['certificateRoots']) ? raw['certificateRoots'] as String : 'system',
      // V2: the default became direct YouTube (2026-10-21); the old key held
      // the old default for everyone who never chose.
      playbackSource: _enumByName(PlaybackSource.values, raw['playbackSourceV2'], PlaybackSource.youtube),
      pipedServer: normalizePipedServer(raw['pipedServer']?.toString() ?? '') ?? '',
      invidiousServer: normalizePipedServer(raw['invidiousServer']?.toString() ?? '') ?? '',
      directRendering: choice('directRendering', {'auto', 'yes', 'no'}, 'auto'),
      autosync: number('autosync', 0, 0, 100),
      audioFilter: filter.length > 4000 || filter.contains(RegExp(r'[\r\n]')) ? '' : filter,
      picture: picture,
      audioDelayMs: number('audioDelayMs', 0, -5000, 5000),
    );
    // The same codecs as the automatic choice stay automatic.
    final chosen = loaded.chosenCodecs;
    return chosen != null ? loaded.withDisabledCodecs(chosen) : loaded;
  }

  /// [value] if it is a comma list of known decoders, else null.
  static String? validHwdec(String? value) {
    if (value == null) return null;
    final known = {for (final (name, _) in [..._windowsHwdec, ..._linuxHwdec, ..._macHwdec]) name};
    final parts = value.split(',').map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty || parts.any((p) => !known.contains(p)) || parts.toSet().length != parts.length) return null;
    return parts.join(',');
  }

  /// Why a custom option cannot be applied, or null when it can.
  static String? customOptionProblem(String key, String value) {
    if (!RegExp(r'^[a-z0-9][a-z0-9_\-/]*$').hasMatch(key)) return tr('Invalid option name');
    if (_blockedOptions.contains(key) || _blockedPrefixes.any(key.startsWith)) return tr("Lumtub doesn't allow setting this option");
    if (value.length > 500 || value.contains(RegExp(r'[\r\n;]'))) return tr('Invalid option value');
    return null;
  }

  static bool isSafeCustomOption(String key, String value) => customOptionProblem(key, value) == null;
}

/// SponsorBlock's categories with the names PiliNara shows for them.
final sponsorCategoryNames = {
  'sponsor': (tr('Sponsor'), tr('Paid promotions, paid referrals and direct ads')),
  'selfpromo': (tr('Self-promotion'), tr('Unpaid promotion: merch, donations or collaborator info')),
  'interaction': (tr('Like and subscribe reminders'), tr('Reminders to like, subscribe or follow')),
  'intro': (tr('Intro'), tr('Intro animations and pause screens with no real content')),
  'outro': (tr('Outro'), tr('End credits, outro animations and next-episode previews')),
  'preview': (tr('Recaps & previews'), tr('Highlights or recap of the previous episode')),
  'music_offtopic': (tr('Music: non-music section'), tr('Non-music segments in music videos')),
  'filler': (tr('Off-topic chatter'), tr('Off-topic segments just for entertainment')),
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

/// The interface's language as a translation target.
TranslationLanguage get interfaceTranslationLanguage => TranslationLanguage.ofTag(currentLanguage.tag) ?? TranslationLanguage.byCode('en');
