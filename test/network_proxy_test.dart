import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/native_core.dart';
import 'package:lumtub/network_proxy.dart';
import 'package:lumtub/player_option_applicator.dart';
import 'package:lumtub/player_settings.dart';
import 'package:lumtub/stream_resolver.dart';

void main() {
  test('reads the Windows proxy as proxy tools write it', () {
    expect(NetworkProxy.parseWindows('127.0.0.1:7890'), 'http://127.0.0.1:7890');
    expect(NetworkProxy.parseWindows('http=127.0.0.1:7890;https=127.0.0.1:7890;socks=127.0.0.1:7891'), 'http://127.0.0.1:7890');
    expect(NetworkProxy.parseWindows('socks=127.0.0.1:7891'), 'socks5://127.0.0.1:7891');
    expect(NetworkProxy.parseWindows(''), isNull);
  });

  test('accepts typed addresses and rejects others', () {
    expect(NetworkProxy.normalize(' 127.0.0.1:7890 '), 'http://127.0.0.1:7890');
    expect(NetworkProxy.normalize('socks5://localhost:1080'), 'socks5://localhost:1080');
    expect(NetworkProxy.normalize('127.0.0.1'), isNull);
    expect(NetworkProxy.normalize('ftp://a:21'), isNull);
    expect(const NetworkProxy('http://127.0.0.1:7890').hostPort, '127.0.0.1:7890');
    expect(const NetworkProxy('socks5://127.0.0.1:7891').isHttp, isFalse);
  });

  test('a SOCKS proxy is asked to look names up itself', () async {
    expect(NetworkProxy.remoteDns('socks5://u:p@127.0.0.1:7891'), 'socks5h://u:p@127.0.0.1:7891');
    expect(NetworkProxy.remoteDns('socks4://127.0.0.1:1080'), 'socks4a://127.0.0.1:1080');
    expect(NetworkProxy.remoteDns('socks5h://h:1'), 'socks5h://h:1');
    expect(NetworkProxy.remoteDns('http://h:1'), 'http://h:1');
    expect((await NetworkProxy.resolve(ProxyMode.custom, 'socks5://127.0.0.1:7891')).url, 'socks5h://127.0.0.1:7891');
  });

  test('the proxy a PAC script names is read by lumtub_core', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) => request.response
      ..write('function FindProxyForURL(url, host) { if (shExpMatch(host, "*.lan")) return "DIRECT"; return "PROXY 127.0.0.1:7890; DIRECT"; }')
      ..close());
    final port = server.port;
    expect((await NetworkProxy.pac('http://127.0.0.1:$port/proxy.pac')).url, 'http://127.0.0.1:7890');
    await server.close(force: true);
    expect((await NetworkProxy.pac('http://127.0.0.1:$port/proxy.pac')).url, isNull);
  }, skip: NativeCore.instance == null ? 'needs lumtub_core' : null);

  test('tells yt-dlp to connect directly only when the proxy is off', () {
    expect(NetworkProxy.direct.ytDlpValue(ProxyMode.off), '');
    expect(NetworkProxy.direct.ytDlpValue(ProxyMode.system), isNull);
    expect(const NetworkProxy('http://h:1').ytDlpValue(ProxyMode.custom), 'http://h:1');
    final resolver = StreamResolver('yt-dlp', proxy: () => 'socks5://h:2', infoDirectory: Directory('x'));
    expect(resolver.arguments('dQw4w9WgXcQ', 'ytdl'), containsAllInOrder(['--proxy', 'socks5://h:2']));
    expect(PlayerOptionApplicator.ytdlRawOptions(const PlayerSettings(), proxy: 'http://h:1'), 'proxy=http://h:1');
  });

  test('the proxy setting is saved and moves old buffer defaults', () {
    final saved = PlayerSettings.fromJson(const PlayerSettings(proxyMode: ProxyMode.custom, proxyAddress: 'http://127.0.0.1:7890').toJson());
    expect(saved.proxyMode, ProxyMode.custom);
    expect(saved.proxyAddress, 'http://127.0.0.1:7890');
    expect(PlayerSettings.fromJson({}).proxyMode, ProxyMode.system);
    final old = PlayerSettings.fromJson({'cacheSeconds': 30, 'cacheMemoryMb': 64});
    expect((old.cacheSeconds, old.cacheMemoryMb), (60, 150));
    final chosen = PlayerSettings.fromJson({'cacheSeconds': 30, 'cacheMemoryMb': 64, 'bufferDefaults': 2});
    expect((chosen.cacheSeconds, chosen.cacheMemoryMb), (30, 64));
  });
}
