import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/yt_dlp_tls.dart';

void main() {
  test('OpenSSL configuration follows 抗量子加密', () {
    expect(YtDlpTls.opensslConfig('prefer'), isNull);
    final off = YtDlpTls.opensslConfig('off')!;
    expect(off, contains('openssl_conf = lumtub_init'));
    expect(off, contains('system_default = lumtub_tls'));
    expect(off, isNot(contains('MLKEM')));
    expect(off, isNot(contains('MinProtocol')));
    final require = YtDlpTls.opensslConfig('require')!;
    expect(require, contains('Groups = X25519MLKEM768:SecP256r1MLKEM768'));
    expect(require, contains('MinProtocol = TLSv1.3'));
  });

  test('the plugin goes where --plugin-dirs finds it, after the isolation', () {
    final folder = Directory.systemTemp.createTempSync('lumtub-tls');
    addTearDown(() => folder.deleteSync(recursive: true));
    final root = YtDlpTls.writePlugin(folder, 'source');
    final sep = Platform.pathSeparator;
    expect(File([root, 'lumtub_tls', 'yt_dlp_plugins', 'extractor', 'lumtub_tls.py'].join(sep)).readAsStringSync(), 'source');
    YtDlpTls.plugins = root;
    addTearDown(() => YtDlpTls.plugins = null);
    expect(YtDlpTls.withPlugin(['--ignore-config', '--no-plugin-dirs', '-j', 'x'], 2), ['--ignore-config', '--no-plugin-dirs', '--plugin-dirs', root, '-j', 'x']);
  });

  test('the plugin is shipped', () {
    final source = File('python/lumtub_tls.py').readAsStringSync();
    expect(source, contains('LUMTUB_CA_FILE'));
    expect(File('pubspec.yaml').readAsStringSync(), contains(YtDlpTls.asset));
  });
}
