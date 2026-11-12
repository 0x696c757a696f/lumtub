import 'dart:convert';
import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';

import 'app_directories.dart';
import 'l10n/l10n.dart';
import 'sun_times.dart';

/// Seed colours offered in Settings; the first is the default. The first
/// six are Lumtub's own, the rest PiliNara's palette.
final accentChoices = <(String, Color)>[
  (tr('YouTube red'), Color(0xFFE53935)),
  (tr('Cyan green'), Color(0xFF26A69A)),
  (tr('Sky blue'), Color(0xFF1E88E5)),
  (tr('Violet'), Color(0xFF7E57C2)),
  (tr('Amber'), Color(0xFFFFB300)),
  (tr('Pink'), Color(0xFFEC407A)),
  (tr('Default green'), Color(0xFF5CB67B)),
  (tr('Orange'), Colors.orange),
  (tr('Yellow'), Colors.yellow),
  (tr('Lime'), Colors.lime),
  (tr('Light green'), Colors.lightGreen),
  (tr('Cyan'), Colors.teal),
  (tr('Teal'), Colors.cyan),
  (tr('Light blue'), Colors.lightBlue),
  (tr('Indigo'), Colors.indigo),
  (tr('Deep purple'), Colors.deepPurple),
  (tr('Blue gray'), Colors.blueGrey),
  (tr('Brown'), Colors.brown),
  (tr('Gray'), Colors.grey),
];

/// A ready-made look: a seed colour and palette style, each shown light
/// or dark as 主题模式 says. [pureBlack] also turns dark backgrounds black.
class ThemePreset {
  const ThemePreset(this._name, this.seed, this.variant, {this.pureBlack = false});
  final String _name;
  String get name => tr(_name);
  final int seed;
  final DynamicSchemeVariant variant;
  final bool pureBlack;

  bool isApplied(AppearanceSettings a) => a.skin.isEmpty && a.palette.isEmpty && !a.systemAccent && a.accentIndex < 0 && a.customAccent == seed && a.schemeVariant == variant && a.pureBlack == pureBlack;

  AppearanceSettings applyTo(AppearanceSettings a) => a.copyWith(skin: '', palette: '', systemAccent: false, accentIndex: -1, customAccent: seed, schemeVariant: variant, pureBlack: pureBlack);
}

const themePresets = [
  ThemePreset('Classic red', 0xFFE53935, DynamicSchemeVariant.tonalSpot),
  ThemePreset('Bay blue', 0xFF1E88E5, DynamicSchemeVariant.fidelity),
  ThemePreset('Forest green', 0xFF2E7D32, DynamicSchemeVariant.tonalSpot),
  ThemePreset('Celadon', 0xFF26A69A, DynamicSchemeVariant.content),
  ThemePreset('Lavender', 0xFF7E57C2, DynamicSchemeVariant.tonalSpot),
  ThemePreset('Sakura', 0xFFEC407A, DynamicSchemeVariant.tonalSpot),
  ThemePreset('Sunset', 0xFFF4511E, DynamicSchemeVariant.vibrant),
  ThemePreset('Graphite', 0xFF607D8B, DynamicSchemeVariant.neutral),
  ThemePreset('OLED black', 0xFF9E9E9E, DynamicSchemeVariant.monochrome, pureBlack: true),
];

/// Material's palette styles with the names PiliNara uses.
final schemeVariantNames = {
  DynamicSchemeVariant.tonalSpot: tr('Default (Tonal Spot)'),
  DynamicSchemeVariant.fidelity: tr('Fidelity'),
  DynamicSchemeVariant.content: tr('Content'),
  DynamicSchemeVariant.vibrant: tr('Vibrant'),
  DynamicSchemeVariant.expressive: tr('Expressive'),
  DynamicSchemeVariant.neutral: tr('Neutral'),
  DynamicSchemeVariant.monochrome: tr('Monochrome'),
  DynamicSchemeVariant.rainbow: tr('Rainbow'),
  DynamicSchemeVariant.fruitSalad: tr('Fruit Salad'),
};

enum PageTransition {
  fade('Fade (default)'),
  zoom('Scale'),
  slide('Swipe up'),
  cupertino('Swipe left or right'),
  none('No animation');

  const PageTransition(this._label);
  final String _label;
  String get label => tr(_label);
}

/// 减少动画: whether page changes, expanding sections and hover effects
/// animate.
enum MotionPreference {
  system('Follow system'),
  reduced('Reduce animations'),
  full('Keep animations');

  const MotionPreference(this._label);
  final String _label;
  String get label => tr(_label);
}

enum NavigationStyle {
  auto('Auto (sidebar on wide windows)'),
  rail('Always use sidebar'),
  bottom('Always use bottom bar');

  const NavigationStyle(this._label);
  final String _label;
  String get label => tr(_label);
}

enum ThumbnailQuality {
  medium('mqdefault', 'Standard (320×180, uses the least data)'),
  high('hqdefault', 'High (480×360, default)'),
  standard('sddefault', 'Higher (640×480)'),
  max('maxresdefault', 'Highest (1280×720, not available for some videos)');

  const ThumbnailQuality(this._file, this._label);
  final String _file;
  String get file => tr(_file);
  final String _label;
  String get label => tr(_label);
}

/// The font bundled with Lumtub and used by default.
const bundledFont = 'Noto Sans CJK SC';

/// Proportional ‘ ’ “ ” taken from the bundled face's pwid forms.
const quotesFont = 'Lumtub Quotes';

/// The default choice: [bundledFont] when the system language is
/// simplified Chinese,
/// which it is made for, else the system UI font.
const autoFont = 'auto';

/// Whether the system language is simplified Chinese, which [bundledFont]
/// is made for.
bool Function() systemFitsBundledFont = () => isSimplifiedChinese(PlatformDispatcher.instance.locale);

bool isSimplifiedChinese(Locale locale) {
  if (locale.languageCode != 'zh') return false;
  final script = locale.scriptCode;
  if (script != null) return script == 'Hans';
  return !const {'TW', 'HK', 'MO'}.contains(locale.countryCode);
}

/// Fonts offered in Settings: automatic, the bundled one, then fonts that
/// ship with Windows and cover Chinese; null is the system UI font.
final fontChoices = <(String?, String)>[
  (autoFont, tr('Automatic (default): Noto Sans CJK SC on a Simplified Chinese system, the system font otherwise')),
  (bundledFont, tr('Noto Sans CJK SC (built-in)')),
  (null, tr('System default')),
  ('Microsoft YaHei UI', tr('Microsoft YaHei')),
  ('DengXian', tr('DengXian')),
];

/// The narrowest a video card may get; set from [AppearanceSettings.cardWidth].
double videoCardMinWidth = 250.0;

/// [AppearanceSettings.compact]: denser video grids, for code that has no
/// settings at hand.
bool compactCards = false;

/// [AppearanceSettings.lowResource], for code that has no settings at hand.
bool lowResourceMode = false;

/// [AppearanceSettings.layout], for the video lists.
VideoLayout videoLayout = VideoLayout.grid;

/// 护眼暖色: when the window is warmed.
enum EyeCare {
  off('Close'),
  always('Always on'),
  sun('Sunset to sunrise'),
  hours('Set hours');

  const EyeCare(this._label);
  final String _label;
  String get label => tr(_label);
}

/// When the dark theme is used instead of [AppearanceSettings.themeMode].
enum DarkSchedule {
  off('By theme mode'),
  sun('Sunset to sunrise'),
  hours('Set hours');

  const DarkSchedule(this._label);
  final String _label;
  String get label => tr(_label);
}

/// How video lists are laid out.
enum VideoLayout {
  grid('Grid (default)'),
  list('List'),
  text('Text only');

  const VideoLayout(this._label);
  final String _label;
  String get label => tr(_label);
}

/// The icon on the window, taskbar, Dock, tray and Android home screen.
/// The installed files (the .exe, the app bundle, the AppImage) keep the
/// classic one.
enum AppIcon {
  classic('Classic', 'assets/app_icons/classic.png'),
  sunlight('Sunlight', 'assets/app_icons/sunlight.png');

  const AppIcon(this._label, this.preview);
  final String _label;
  String get label => tr(_label);
  final String preview;
}

int _hour(Object? raw, int fallback) => raw is int && raw >= 0 && raw < 24 ? raw : fallback;

T _byName<T extends Enum>(List<T> values, Object? name, T fallback) => values.where((v) => v.name == name).firstOrNull ?? fallback;

class AppearanceSettings {
  final ThemeMode themeMode;
  /// An index into [accentChoices], or -1 for [customAccent].
  final int accentIndex;
  final int customAccent;
  /// Follow the Windows accent colour instead of the chosen one.
  final bool systemAccent;
  final DynamicSchemeVariant schemeVariant;
  /// True black backgrounds in dark mode.
  final bool pureBlack;
  /// Smaller rows, menus and fields, so more fits on screen.
  final bool compact;
  final String? fontFamily;
  final double textScale;
  final PageTransition transition;
  final MotionPreference motion;
  final NavigationStyle navigation;
  /// The narrowest a video card may get before a column is dropped.
  final double cardWidth;
  final ThumbnailQuality thumbnailQuality;
  final bool darkWatchPage;
  final bool showStatusBar;
  /// The interface language; it applies after a restart.
  final AppLanguage language;
  /// A [Palette] id from lib/ui/palettes.dart, or '' for the neutral one.
  final String palette;
  /// A skin id (lib/skins), or '' for none. A skin sets the whole look and
  /// comes before [palette], the accent and the theme mode.
  final String skin;
  /// Under a skin with its own title bar: keep the system's instead.
  final bool systemTitleBar;
  /// Under a skin with a menu bar: no title bar; the window buttons sit in
  /// the menu bar.
  final bool hideTitleBar;
  /// Under a glass skin: how solid its panes are, 0.3 to 1.
  final double glassOpacity;
  /// Whether a skin's pictures and landscape lie behind the pages; off
  /// leaves its page colour alone.
  final bool skinBackground;
  final EyeCare eyeCare;
  /// How warm 护眼暖色 makes the window, 0.1 to 1: the colour
  /// temperature of the light, from 6040 K down to 1900 K
  /// ([kelvinOf], [warmthOf]).
  final double warmth;

  /// The colour temperature [warmth] stands for, and back: the window is
  /// white at 6500 K, a candle at 1900 K.
  static int kelvinOf(double warmth) => (6500 - warmth * 4600).round();
  static double warmthOf(int kelvin) => ((6500 - kelvin) / 4600).clamp(0.1, 1.0);
  /// [EyeCare.hours]: from this hour until [eyeCareEnd].
  final int eyeCareStart;
  final int eyeCareEnd;
  final DarkSchedule darkSchedule;
  /// [DarkSchedule.hours]: dark from this hour until [darkEnd].
  final int darkStart;
  final int darkEnd;
  /// 低占用模式: no animations, small thumbnails, no hover loading and a
  /// smaller image cache.
  final bool lowResource;
  final VideoLayout layout;
  final AppIcon appIcon;

  const AppearanceSettings({
    this.themeMode = ThemeMode.system,
    this.accentIndex = 0,
    this.customAccent = 0xFFE53935,
    this.systemAccent = false,
    this.schemeVariant = DynamicSchemeVariant.tonalSpot,
    this.pureBlack = false,
    this.compact = false,
    this.fontFamily = autoFont,
    this.textScale = 1.0,
    this.transition = PageTransition.fade,
    this.motion = MotionPreference.system,
    this.navigation = NavigationStyle.auto,
    this.cardWidth = 250,
    this.thumbnailQuality = ThumbnailQuality.high,
    this.darkWatchPage = false,
    this.showStatusBar = true,
    this.language = AppLanguage.system,
    this.palette = '',
    this.skin = '',
    this.systemTitleBar = false,
    this.hideTitleBar = false,
    this.glassOpacity = 1,
    this.skinBackground = true,
    this.eyeCare = EyeCare.off,
    this.warmth = 0.4,
    this.eyeCareStart = 20,
    this.eyeCareEnd = 7,
    this.darkSchedule = DarkSchedule.off,
    this.darkStart = 19,
    this.darkEnd = 7,
    this.lowResource = false,
    this.layout = VideoLayout.grid,
    this.appIcon = AppIcon.classic,
  });

  /// Whether 护眼暖色 is on at [now].
  /// How warm the window is at [now]: [warmth] while the warm light is
  /// on. Following the sun it moves with the sun's height through dusk
  /// and dawn ([SunTimes.nightness]); on the hours set, over the half
  /// hour either side. Either way in twelve steps, so the window is
  /// redrawn only that often.
  double warmthAt(DateTime now) {
    if (eyeCare == EyeCare.off) return 0;
    if (eyeCare == EyeCare.always) return warmth;
    if (eyeCare == EyeCare.sun) return warmth * (SunTimes.here.nightness(now) * 12).round() / 12;
    final step = DateTime.fromMillisecondsSinceEpoch(now.millisecondsSinceEpoch ~/ _step.inMilliseconds * _step.inMilliseconds);
    var on = 0;
    for (var i = -6; i < 6; i++) {
      if (warmAt(step.add(_step * i + _step ~/ 2))) on++;
    }
    return warmth * on / 12;
  }

  static const _step = Duration(minutes: 5);

  bool warmAt(DateTime now) => switch (eyeCare) {
        EyeCare.off => false,
        EyeCare.always => true,
        EyeCare.sun => SunTimes.here.isNight(now),
        EyeCare.hours => inHours(now, eyeCareStart, eyeCareEnd),
      };

  /// The theme mode at [now]: [themeMode], or light and dark by [darkSchedule].
  ThemeMode themeModeAt(DateTime now) => switch (darkSchedule) {
        DarkSchedule.off => themeMode,
        DarkSchedule.sun => SunTimes.here.isNight(now) ? ThemeMode.dark : ThemeMode.light,
        DarkSchedule.hours => inHours(now, darkStart, darkEnd) ? ThemeMode.dark : ThemeMode.light,
      };

  /// The thumbnails asked for: the smallest in 低占用模式.
  ThumbnailQuality get effectiveThumbnails => lowResource ? ThumbnailQuality.medium : thumbnailQuality;

  /// Animations as chosen, none in 低占用模式.
  MotionPreference get effectiveMotion => lowResource ? MotionPreference.reduced : motion;

  /// The chosen colour; [systemAccent] is resolved by the app.
  Color get accent => accentIndex < 0 ? Color(customAccent) : accentChoices[accentIndex].$2;

  String get accentLabel => systemAccent ? tr('Follow Windows accent color') : accentIndex < 0 ? tr('Custom') : accentChoices[accentIndex].$1;

  AppearanceSettings copyWith({
    ThemeMode? themeMode,
    int? accentIndex,
    int? customAccent,
    bool? systemAccent,
    DynamicSchemeVariant? schemeVariant,
    bool? pureBlack,
    bool? compact,
    String? fontFamily,
    bool clearFontFamily = false,
    double? textScale,
    PageTransition? transition,
    MotionPreference? motion,
    NavigationStyle? navigation,
    double? cardWidth,
    ThumbnailQuality? thumbnailQuality,
    bool? darkWatchPage,
    bool? showStatusBar,
    AppLanguage? language,
    String? palette,
    String? skin,
    bool? systemTitleBar,
    bool? hideTitleBar,
    double? glassOpacity,
    bool? skinBackground,
    EyeCare? eyeCare,
    double? warmth,
    int? eyeCareStart,
    int? eyeCareEnd,
    DarkSchedule? darkSchedule,
    int? darkStart,
    int? darkEnd,
    bool? lowResource,
    VideoLayout? layout,
    AppIcon? appIcon,
  }) =>
      AppearanceSettings(
        themeMode: themeMode ?? this.themeMode,
        accentIndex: accentIndex ?? this.accentIndex,
        customAccent: customAccent ?? this.customAccent,
        systemAccent: systemAccent ?? this.systemAccent,
        schemeVariant: schemeVariant ?? this.schemeVariant,
        pureBlack: pureBlack ?? this.pureBlack,
        compact: compact ?? this.compact,
        fontFamily: clearFontFamily ? null : fontFamily ?? this.fontFamily,
        textScale: textScale ?? this.textScale,
        transition: transition ?? this.transition,
        motion: motion ?? this.motion,
        navigation: navigation ?? this.navigation,
        cardWidth: cardWidth ?? this.cardWidth,
        thumbnailQuality: thumbnailQuality ?? this.thumbnailQuality,
        darkWatchPage: darkWatchPage ?? this.darkWatchPage,
        showStatusBar: showStatusBar ?? this.showStatusBar,
        language: language ?? this.language,
        palette: palette ?? this.palette,
        skin: skin ?? this.skin,
        systemTitleBar: systemTitleBar ?? this.systemTitleBar,
        hideTitleBar: hideTitleBar ?? this.hideTitleBar,
        glassOpacity: glassOpacity ?? this.glassOpacity,
        skinBackground: skinBackground ?? this.skinBackground,
        eyeCare: eyeCare ?? this.eyeCare,
        warmth: warmth ?? this.warmth,
        eyeCareStart: eyeCareStart ?? this.eyeCareStart,
        eyeCareEnd: eyeCareEnd ?? this.eyeCareEnd,
        darkSchedule: darkSchedule ?? this.darkSchedule,
        darkStart: darkStart ?? this.darkStart,
        darkEnd: darkEnd ?? this.darkEnd,
        lowResource: lowResource ?? this.lowResource,
        layout: layout ?? this.layout,
        appIcon: appIcon ?? this.appIcon,
      );

  /// The family text is drawn in; null is the system UI font.
  String? get font => fontFamily == autoFont ? (systemFitsBundledFont() ? bundledFont : null) : fontFamily;

  /// What a theme is built from; themes are rebuilt only when it changes.
  Object themeKey(Color seed) => (seed, schemeVariant, pureBlack, compact, font, transition, palette, skin);

  Map<String, dynamic> toJson() => {
        'themeMode': themeMode.name,
        'accentIndex': accentIndex,
        'customAccent': customAccent,
        'systemAccent': systemAccent,
        'schemeVariant': schemeVariant.name,
        'pureBlack': pureBlack,
        'compact': compact,
        'fontFamily': fontFamily ?? 'system',
        'fontVersion': 2,
        'textScale': textScale,
        'transition': transition.name,
        'motion': motion.name,
        'navigation': navigation.name,
        'cardWidth': cardWidth,
        'thumbnailQuality': thumbnailQuality.name,
        'darkWatchPage': darkWatchPage,
        'showStatusBar': showStatusBar,
        'language': language.tag,
        'palette': palette,
        'skin': skin,
        'systemTitleBar': systemTitleBar,
        'hideTitleBar': hideTitleBar,
        'glassOpacity': glassOpacity,
        'skinBackground': skinBackground,
        'eyeCare': eyeCare.name,
        'warmth': warmth,
        'eyeCareStart': eyeCareStart,
        'eyeCareEnd': eyeCareEnd,
        'darkSchedule': darkSchedule.name,
        'darkStart': darkStart,
        'darkEnd': darkEnd,
        'lowResource': lowResource,
        'layout': layout.name,
        'appIcon': appIcon.name,
      };

  factory AppearanceSettings.fromJson(Object? raw) {
    if (raw is! Map) return const AppearanceSettings();
    final mode = ThemeMode.values.where((m) => m.name == raw['themeMode']).firstOrNull ?? ThemeMode.system;
    final index = raw['accentIndex'];
    final custom = raw['customAccent'];
    final font = raw['fontFamily']?.toString();
    final scale = raw['textScale'];
    final width = raw['cardWidth'];
    return AppearanceSettings(
      themeMode: mode,
      accentIndex: index is int && index >= -1 && index < accentChoices.length ? index : 0,
      customAccent: custom is int ? custom | 0xFF000000 : 0xFFE53935,
      systemAccent: raw['systemAccent'] == true,
      schemeVariant: _byName(DynamicSchemeVariant.values, raw['schemeVariant'], DynamicSchemeVariant.tonalSpot),
      pureBlack: raw['pureBlack'] == true,
      compact: raw['compact'] == true,
      // Earlier builds wrote nothing for the system font, and wrote the
      // bundled one as their default; both now mean automatic.
      fontFamily: font == 'system'
          ? null
          : font == null || font.trim().isEmpty || (font == bundledFont && raw['fontVersion'] != 2)
              ? autoFont
              : font,
      textScale: scale is num ? scale.toDouble().clamp(0.8, 1.4) : 1.0,
      transition: _byName(PageTransition.values, raw['transition'], PageTransition.fade),
      motion: _byName(MotionPreference.values, raw['motion'], MotionPreference.system),
      navigation: _byName(NavigationStyle.values, raw['navigation'], NavigationStyle.auto),
      cardWidth: width is num ? width.toDouble().clamp(180, 420) : 250,
      thumbnailQuality: _byName(ThumbnailQuality.values, raw['thumbnailQuality'], ThumbnailQuality.high),
      darkWatchPage: raw['darkWatchPage'] == true,
      showStatusBar: raw['showStatusBar'] != false,
      language: AppLanguage.parse(raw['language']),
      // The colour schemes are skins now: a saved one becomes its skin.
      palette: '',
      skin: switch ((raw['skin'], raw['palette'])) {
        (final String skin, _) when skin.isNotEmpty => skin,
        (_, final String palette) when palette.isNotEmpty => paletteSkinId(palette),
        _ => '',
      },
      systemTitleBar: raw['systemTitleBar'] == true,
      hideTitleBar: raw['hideTitleBar'] == true,
      glassOpacity: raw['glassOpacity'] is num ? (raw['glassOpacity'] as num).toDouble().clamp(0.3, 1.0) : 1,
      skinBackground: raw['skinBackground'] != false,
      eyeCare: _byName(EyeCare.values, raw['eyeCare'], EyeCare.off),
      warmth: raw['warmth'] is num ? (raw['warmth'] as num).toDouble().clamp(0.1, 1.0) : 0.4,
      eyeCareStart: _hour(raw['eyeCareStart'], 20),
      eyeCareEnd: _hour(raw['eyeCareEnd'], 7),
      darkSchedule: _byName(DarkSchedule.values, raw['darkSchedule'], DarkSchedule.off),
      darkStart: _hour(raw['darkStart'], 19),
      darkEnd: _hour(raw['darkEnd'], 7),
      lowResource: raw['lowResource'] == true,
      layout: _byName(VideoLayout.values, raw['layout'], VideoLayout.grid),
      appIcon: _byName(AppIcon.values, raw['appIcon'], AppIcon.classic),
    );
  }
}

/// Reads the Windows accent colour (Settings › Personalisation › Colours).
/// Returns null when it cannot be read, such as outside Windows.
Future<Color?> readWindowsAccent() async {
  if (!Platform.isWindows) return null;
  try {
    final result = await Process.run('reg', ['query', r'HKCU\Software\Microsoft\Windows\DWM', '/v', 'AccentColor']);
    final match = RegExp(r'AccentColor\s+REG_DWORD\s+0x([0-9a-fA-F]+)').firstMatch('${result.stdout}');
    if (match == null) return null;
    // Stored as 0xAABBGGRR.
    final abgr = int.parse(match[1]!, radix: 16);
    return Color.fromARGB(0xFF, abgr & 0xFF, (abgr >> 8) & 0xFF, (abgr >> 16) & 0xFF);
  } catch (_) {
    return null;
  }
}

class AppearanceSettingsStore {
  final File file;
  AppearanceSettingsStore(AppDirectories directories) : file = File('${directories.config.path}${Platform.pathSeparator}appearance.json');

  Future<AppearanceSettings> load() async {
    if (!await file.exists()) return const AppearanceSettings();
    try {
      return AppearanceSettings.fromJson(jsonDecode(await file.readAsString()));
    } catch (e) {
      await setBrokenFileAside(file, e);
      return const AppearanceSettings();
    }
  }

  final _writes = WriteQueue();

  Future<void> save(AppearanceSettings settings) {
    final text = jsonEncode(settings.toJson());
    return _writes.run(() => writeFileAtomic(file, text));
  }
}

/// The skin a colour scheme saved before 0.2.30 became: ricePaper → rice-paper.
String paletteSkinId(String palette) => palette.replaceAllMapped(RegExp('[A-Z]'), (m) => '-${m[0]!.toLowerCase()}');
