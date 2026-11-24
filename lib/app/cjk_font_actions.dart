part of 'app_controller.dart';

/// Japanese, Korean and traditional Chinese faces downloaded as data packs
/// where the system has none (CjkFontPacks): a Linux without Noto Sans
/// CJK, and libass on iOS.
extension CjkFontActions on AppController {
  /// Downloads the face for [language]'s character forms when this system
  /// needs one and has not got it yet, then uses it. Asked once per forms
  /// in a run; anything else returns at once.
  Future<void> ensureCjkFont(String language) async {
    if (!(Platform.isLinux || Platform.isIOS)) return;
    final forms = cjkFormOf(language);
    final packs = this.packs;
    if (forms == null || packs == null || downloadedCjkFamilies.containsKey(forms) || !_cjkFontsAsked.add(forms)) return;
    if (!await CjkFontPacks.needed(forms)) return;
    final id = CjkFontPacks.ids[forms]!;
    try {
      if (packs.installedOf(id) == null) {
        if (!packs.catalog.any((p) => p.id == id)) await packs.refresh();
        if (!packs.catalog.any((p) => p.id == id && p.suitsThisBuild)) {
          logInfo('No data pack $id to download');
          return;
        }
        logInfo('Downloading $id: this system has no font for $forms');
        await packs.install(id);
      }
      await useDownloadedCjkFonts();
    } catch (e) {
      logWarn('Could not get the font pack $id: $e');
    }
  }

  /// Puts the installed font packs to use: in Flutter's text, and in
  /// libass on Linux and iOS.
  Future<void> useDownloadedCjkFonts() async {
    final packs = this.packs;
    if (packs == null) return;
    if (await CjkFontPacks.load(packs)) _update(() => cjkFontsRevision++);
    final platform = player?.platform;
    if (platform is! NativePlayer) return;
    if (Platform.isIOS) await _prepareIosSubtitleFonts(platform);
    if (Platform.isLinux) await _useDownloadedSubtitleFonts(platform);
  }

  /// libass on iOS draws in the app's own fonts only, as on Android, picked
  /// by the script of the text, with the downloaded ones beside them.
  /// Looking through Core Text instead ran for seconds on mpv's video
  /// thread on iOS 27, holding the OSD lock (the crash report: core and
  /// main thread waiting on it), which stalled playback and got the app
  /// killed in the background.
  ///
  /// [cache] is the cache folder while starting up, before [directories]
  /// is set.
  Future<void> _prepareIosSubtitleFonts(NativePlayer platform, {String? cache}) async {
    cache ??= directories?.cache.path;
    if (cache == null) return;
    final packs = this.packs;
    final app = File(Platform.resolvedExecutable).parent.path;
    final fonts = await AndroidSubtitleFonts.prepareIos(
      '$cache/subtitle-fonts',
      flutterFonts: '$app/Frameworks/App.framework/flutter_assets/assets/fonts',
      bundled: '$app/SubtitleFonts',
      downloaded: packs == null
          ? const {}
          : {
              for (final MapEntry(key: forms, value: file) in CjkFontPacks.installedFiles(packs).entries) forms: (file, CjkFontPacks.families[forms]!),
            },
    );
    if (fonts == null) {
      logInfo('No bundled subtitle fonts in $app');
      return;
    }
    for (final MapEntry(:key, :value) in {
      'sub-font-provider': 'none',
      'sub-fonts-dir': fonts,
      // The bullet chat is drawn as OSD.
      'osd-font-provider': 'none',
      'osd-fonts-dir': fonts,
      'osd-font': PlayerSettings.iosSubtitleFont,
    }.entries) {
      await platform.setProperty(key, value).catchError((Object e) => logDebug(() => 'Could not set $key: $e'));
    }
  }

  /// On Linux: libass finds the downloaded fonts beside the system's.
  Future<void> _useDownloadedSubtitleFonts(NativePlayer platform, {String? cache}) async {
    cache ??= directories?.cache.path;
    final packs = this.packs;
    if (cache == null || packs == null) return;
    final folder = CjkFontPacks.linkFolder(packs, '$cache/downloaded-fonts');
    if (folder == null) return;
    await platform.setProperty('sub-fonts-dir', folder).catchError((Object e) => logDebug(() => 'Could not set the subtitle fonts: $e'));
  }
}
