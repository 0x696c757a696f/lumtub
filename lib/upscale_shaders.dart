import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;

import 'app_log.dart';
import 'device.dart';
import 'player_settings.dart';

/// 画质增强: mpv user shaders (assets/shaders) that rebuild detail when a
/// picture is drawn larger than it is. Each one only runs when the player
/// is at least 1.2 to 1.4 times the picture's size, so a 1080p video on a
/// 1080p screen costs nothing extra.
///
/// libmpv reads shaders from files, and on Android the assets are inside
/// the package, so the chosen one is copied to the data folder first
/// ([prepare]); [option] is empty until it is there.
abstract final class UpscaleShaders {
  static Directory? _folder;
  static final _ready = <Upscaling>{};

  /// The asset files of [tier], in the order mpv runs them.
  static List<String> files(Upscaling tier) => switch (tier) {
        Upscaling.off => const [],
        Upscaling.light => const ['ravu-lite-ar-r3.glsl'],
        Upscaling.strong => const ['FSRCNNX_x2_8-0-4-1.glsl'],
        Upscaling.anime => const ['anime4k-a.glsl'],
      };

  /// The tiers this device offers. iOS draws the picture with
  /// AVFoundation, where mpv's shaders do not run; a TV box's GPU has no
  /// room for them; a phone or tablet gets the light one only.
  static List<Upscaling> get offered {
    if (Platform.isIOS || Device.tv) return const [Upscaling.off];
    if (Platform.isAndroid) return const [Upscaling.off, Upscaling.light];
    return Upscaling.values;
  }

  /// [tier], or off where this device does not offer it.
  static Upscaling usable(Upscaling tier) => offered.contains(tier) ? tier : Upscaling.off;

  /// Copies [tier]'s shaders into [data]/upscale unless they are there
  /// already. Failing leaves the picture as it is.
  static Future<void> prepare(Directory? data, Upscaling tier) async {
    tier = usable(tier);
    if (data != null) _folder = Directory('${data.path}${Platform.pathSeparator}upscale');
    final folder = _folder;
    if (tier == Upscaling.off || folder == null || _ready.contains(tier)) return;
    try {
      await folder.create(recursive: true);
      for (final name in files(tier)) {
        final bytes = (await rootBundle.load('assets/shaders/$name')).buffer.asUint8List();
        final file = File('${folder.path}${Platform.pathSeparator}$name');
        if (await file.exists() && await file.length() == bytes.length) continue;
        final part = File('${file.path}.part');
        await part.writeAsBytes(bytes, flush: true);
        await part.rename(file.path);
      }
      _ready.add(tier);
    } catch (e) {
      logWarn('Could not set up the upscaling shaders: $e');
    }
  }

  /// mpv's `glsl-shaders` for [tier]: the files joined with the system's
  /// path separator, or empty.
  static String option(Upscaling tier) {
    tier = usable(tier);
    final folder = _folder;
    if (folder == null || !_ready.contains(tier)) return '';
    return [for (final name in files(tier)) '${folder.path}${Platform.pathSeparator}$name'].join(Platform.isWindows ? ';' : ':');
  }
}
