import 'dart:io';

import 'package:flutter/services.dart';

import 'app_log.dart';
import 'native_core.dart';

/// What every yt-dlp run is given so that its own HTTPS follows 证书来源
/// and 抗量子加密 as the core's does: Lumtub's plugin (python/lumtub_tls.py)
/// loads the chosen certificate authorities, and an OpenSSL configuration
/// sets the key exchange groups and TLS versions.
///
/// yt-dlp's builds carry OpenSSL 3.5, which offers X25519MLKEM768 first
/// on its own, so 优先 needs no configuration; 关闭 leaves the hybrid out,
/// 必须 offers nothing else and no TLS 1.2.
abstract final class YtDlpTls {
  static const asset = 'python/lumtub_tls.py';

  /// The folder to pass with --plugin-dirs; null before [configure] or
  /// when the plugin could not be written.
  static String? plugins;

  /// Added to every yt-dlp run's environment.
  static Map<String, String> environment = const {};

  static String? _source;

  /// Writes the plugin, the certificate list of [roots] and the OpenSSL
  /// configuration of [quantum] under [folder].
  static Future<void> configure(Directory folder, {required String roots, required String quantum}) async {
    final sep = Platform.pathSeparator;
    try {
      _source ??= await rootBundle.loadString(asset);
      plugins = writePlugin(folder, _source!);
    } catch (e) {
      logWarn('Could not set up the yt-dlp TLS plugin: $e');
      plugins = null;
    }
    final env = <String, String>{};
    try {
      final tls = Directory('${folder.path}${sep}tls')..createSync(recursive: true);
      final pem = NativeCore.rootsPem(roots);
      if (pem != null) {
        final file = File('${tls.path}${sep}roots-$roots.pem');
        _writeIfChanged(file, pem);
        env['LUMTUB_CA_FILE'] = file.path;
        env['LUMTUB_CA_ONLY'] = roots == 'system' ? '0' : '1';
      } else if (roots != 'system') {
        // The list could not be had: nothing is trusted rather than
        // everything yt-dlp would trust.
        env['LUMTUB_CA_FILE'] = '${tls.path}${sep}roots-$roots.pem';
        env['LUMTUB_CA_ONLY'] = '1';
        logWarn('No $roots certificate list for yt-dlp; its HTTPS will fail');
      }
      final config = opensslConfig(quantum);
      if (config != null) {
        final file = File('${tls.path}${sep}openssl-$quantum.cnf');
        _writeIfChanged(file, config);
        env['OPENSSL_CONF'] = file.path;
      }
      env['LUMTUB_PQ'] = quantum;
    } catch (e) {
      logWarn('Could not write yt-dlp TLS settings: $e');
    }
    environment = Map.unmodifiable(env);
  }

  /// Writes [source] where --plugin-dirs [folder]/yt-dlp-tls finds it and
  /// gives back that folder.
  static String writePlugin(Directory folder, String source) {
    final sep = Platform.pathSeparator;
    final root = '${folder.path}${sep}yt-dlp-tls';
    final file = File([root, 'lumtub_tls', 'yt_dlp_plugins', 'extractor', 'lumtub_tls.py'].join(sep));
    file.parent.createSync(recursive: true);
    _writeIfChanged(file, source);
    return root;
  }

  /// The OpenSSL configuration for 抗量子加密 [quantum]; none for 优先,
  /// OpenSSL's own default.
  static String? opensslConfig(String quantum) {
    final lines = switch (quantum) {
      'off' => ['Groups = X25519:secp256r1:X448:secp384r1:secp521r1:ffdhe2048:ffdhe3072'],
      'require' => ['Groups = X25519MLKEM768:SecP256r1MLKEM768', 'MinProtocol = TLSv1.3'],
      _ => null,
    };
    if (lines == null) return null;
    return [
      'openssl_conf = lumtub_init',
      '',
      '[lumtub_init]',
      'ssl_conf = lumtub_ssl',
      '',
      '[lumtub_ssl]',
      'system_default = lumtub_tls',
      '',
      '[lumtub_tls]',
      ...lines,
      '',
    ].join('\n');
  }

  /// [arguments] of a yt-dlp run with the plugin folder after the leading
  /// [lead] isolation arguments (--no-plugin-dirs would clear it).
  static List<String> withPlugin(List<String> arguments, int lead) {
    final folder = plugins;
    if (folder == null) return arguments;
    return [...arguments.take(lead), '--plugin-dirs', folder, ...arguments.skip(lead)];
  }

  static void _writeIfChanged(File file, String text) {
    if (file.existsSync() && file.readAsStringSync() == text) return;
    file.writeAsStringSync(text, flush: true);
  }
}
