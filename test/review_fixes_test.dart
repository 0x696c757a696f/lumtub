import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lumtub/app_updater.dart';
import 'package:lumtub/cast/cast_subtitles.dart';
import 'package:lumtub/cast/chromecast.dart';
import 'package:lumtub/cast/dlna.dart';
import 'package:lumtub/library_store.dart';
import 'package:lumtub/media_url_policy.dart';
import 'package:lumtub/network_proxy.dart';
import 'package:lumtub/skins/skin.dart';
import 'package:lumtub/translation_services.dart';
import 'package:lumtub/ui/common.dart';
import 'package:lumtub/watch_time.dart';

void main() {
  group('Chromecast framing', () {
    test('a negative or oversized length is a format error', () {
      // Field 1, length-delimited, whose length varint is ten bytes: 2^63 - 1 and 2^64 - 1.
      final negative = Uint8List.fromList([0x0A, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x01, 0x41]);
      expect(() => decodeCastMessage(negative), throwsFormatException);
      final huge = Uint8List.fromList([0x0A, 0xFF, 0xFF, 0xFF, 0xFF, 0x7F, 0x41]);
      expect(() => decodeCastMessage(huge), throwsFormatException);
      final reader = CastFrameReader();
      expect(() => reader.add([0, 0, 0, negative.length, ...negative]), throwsFormatException);
    });
  });

  group('DLNA', () {
    const xml = '''<root><URLBase>http://10.0.0.9:80/</URLBase><device><friendlyName>TV</friendlyName><UDN>uuid:1</UDN><serviceList>
<service><serviceType>urn:schemas-upnp-org:service:AVTransport:1</serviceType><controlURL>/ok</controlURL></service>
<service><serviceType>urn:schemas-upnp-org:service:RenderingControl:1</serviceType><controlURL>http://169.254.169.254/latest</controlURL></service>
</serviceList></device></root>''';

    test('control addresses stay on the host that sent the description', () {
      final description = parseDeviceDescription(xml, Uri.parse('http://192.168.1.20:8080/desc.xml'));
      // The foreign URLBase is ignored and the absolute foreign address dropped.
      expect(description.services.map((s) => s.controlUrl.toString()), ['http://192.168.1.20:8080/ok']);
      final same = parseDeviceDescription(xml.replaceAll('10.0.0.9:80', '192.168.1.20:8080'), Uri.parse('http://192.168.1.20:8080/desc.xml'));
      expect(same.services.single.controlUrl.host, '192.168.1.20');
    });

    test('xmlUnescape keeps code points that are not characters', () {
      expect(xmlUnescape('&#65;&#x1F600;'), 'A\u{1F600}');
      expect(xmlUnescape('&#x110000;'), '&#x110000;');
      expect(xmlUnescape('&#xD800;'), '&#xD800;');
      expect(xmlUnescape('&#0;'), '&#0;');
      expect(xmlUnescape('&#99999999999999999999;'), '&#99999999999999999999;');
    });
  });

  test('subtitles are served under a random path', () async {
    final server = CastSubtitleServer.instance;
    addTearDown(server.close);
    const cue = (start: Duration(seconds: 1), end: Duration(seconds: 2), text: 'a');
    final one = await server.register([cue], host: '127.0.0.1');
    final two = await server.register([cue], host: '127.0.0.1');
    final path = Uri.parse(one.vtt).pathSegments;
    expect(path.first, matches(RegExp(r'^[0-9a-f]{32}$')));
    expect(Uri.parse(two.vtt).pathSegments.first, isNot(path.first));
    final client = HttpClient();
    addTearDown(client.close);
    final guess = await (await client.getUrl(Uri.parse(one.vtt).replace(path: '/sub1.vtt'))).close();
    expect(guess.statusCode, 404);
    await guess.drain<void>();
  });

  group('broken files are kept aside', () {
    late Directory dir;
    setUp(() async => dir = await Directory.systemTemp.createTemp('lumtub_broken'));
    tearDown(() => dir.delete(recursive: true));

    test('library.json', () async {
      final file = File('${dir.path}/library.json')..writeAsStringSync('{"favorites": [');
      final library = LibraryStore(file);
      await library.load();
      expect(library.favorites, isEmpty);
      expect(file.existsSync(), isFalse);
      expect(File('${file.path}.broken').readAsStringSync(), '{"favorites": [');
    });

    test('library.json that is not an object', () async {
      final file = File('${dir.path}/library.json')..writeAsStringSync('[1]');
      await LibraryStore(file).load();
      expect(File('${file.path}.broken').existsSync(), isTrue);
    });

    test('watch_time.json', () async {
      final file = File('${dir.path}/watch_time.json')..writeAsStringSync('nope');
      final time = WatchTime(file);
      await time.load();
      expect(time.isEmpty, isTrue);
      expect(File('${file.path}.broken').readAsStringSync(), 'nope');
      // A missing file is not a broken one.
      await WatchTime(File('${dir.path}/none.json')).load();
      expect(File('${dir.path}/none.json.broken').existsSync(), isFalse);
    });
  });

  group('API keys follow their host', () {
    const openai = TranslationConfig(aiPreset: 'openai');

    test('a key is only used for the host it was saved for', () {
      const keys = {'ai@api.openai.com': 'sk-1'};
      expect(aiKeyFor(openai, keys), 'sk-1');
      expect(aiKeyFor(const TranslationConfig(aiPreset: 'deepseek'), keys), '');
      expect(aiKeyFor(const TranslationConfig(aiPreset: 'custom', aiBaseUrl: 'https://API.OpenAI.com:8443/v1'), keys), '');
      expect(aiKeyFor(const TranslationConfig(aiPreset: 'custom', aiBaseUrl: 'https://API.OpenAI.com/v1'), keys), 'sk-1');
      expect(aiKeyFor(const TranslationConfig(aiPreset: 'custom', aiBaseUrl: 'https://evil.example/v1'), keys), '');
      expect(aiServiceFor(const TranslationConfig(aiPreset: 'custom', aiBaseUrl: 'https://evil.example/v1', aiModel: 'm'), keys, _client), isNotNull, reason: 'custom endpoints may run without a key, but get none');
    });

    test('the old single key moves to the host it was saved for', () {
      final migrated = migrateKeyHosts(openai, const {'ai': 'sk-old', 'speech': 'gsk', 'deepl': 'd'});
      expect(migrated, {'ai@api.openai.com': 'sk-old', 'speech@api.groq.com': 'gsk', 'deepl': 'd'});
      expect(aiKeyFor(openai, migrated), 'sk-old');
      expect(migrateKeyHosts(openai, migrated), same(migrated));
      // Without an address the key is not kept for a host it cannot be tied to.
      expect(migrateKeyHosts(const TranslationConfig(aiPreset: 'custom'), const {'ai': 'x'}), isEmpty);
    });

    test('speech uses its own key for its host, else the AI key of that host', () {
      const config = TranslationConfig(aiPreset: 'openai', speechPreset: 'openai');
      expect(speechKeyFor(config, const {'ai@api.openai.com': 'sk'}), 'sk');
      expect(speechKeyFor(config, const {'ai@api.openai.com': 'sk', 'speech@api.openai.com': 'own'}), 'own');
      expect(speechKeyFor(config, const {'speech@api.groq.com': 'gsk'}), '');
      const custom = TranslationConfig(speechPreset: 'custom', speechBaseUrl: 'https://asr.example/v1');
      expect(speechKeyFor(custom, const {'speech@api.groq.com': 'gsk', 'ai@api.openai.com': 'sk'}), '');
      expect(speechKeyFor(custom, const {'speech@asr.example': 'k'}), 'k');
    });
  });

  test('a package that fails its check before installing is deleted and not started', () async {
    final dir = await Directory.systemTemp.createTemp('lumtub_updater');
    addTearDown(() => dir.delete(recursive: true));
    final updater = AppUpdater(client: _client, directory: dir, download: (asset, into, onProgress) async => throw UnimplementedError());
    final package = File('${dir.path}/Lumtub-setup.exe')..writeAsBytesSync([1, 2, 3]);
    updater.ready = package;
    expect(await updater.install(), isFalse);
    expect(package.existsSync(), isFalse);
    expect(updater.ready, isNull);
    expect(updater.installError, isNotNull);
  });

  test('only web links go to the browser', () {
    expect(webLink('https://example.com/a?b=1&c=2'), isNotNull);
    expect(webLink('http://example.com'), isNotNull);
    expect(webLink('/home/user/.local/share/lumtub'), isNull);
    expect(webLink(r'C:\Users\me\AppData\Roaming\Lumtub'), isNull);
    expect(webLink('file:///etc/passwd'), isNull);
    expect(webLink('lumtub://x'), isNull);
  });

  group('proxy credentials', () {
    test('an http proxy keeps its login', () {
      expect(NetworkProxy.normalize('http://u:p@127.0.0.1:7890'), 'http://u:p@127.0.0.1:7890');
      expect(NetworkProxy.normalize('u:p@127.0.0.1:7890'), 'http://u:p@127.0.0.1:7890');
      expect(const NetworkProxy('http://u:p@h:1').hostPort, 'u:p@h:1');
      expect(const NetworkProxy('http://h:1').hostPort, 'h:1');
      expect(const NetworkProxy('http://u:p@h:1').redacted, 'http://h:1');
    });

    test('yt-dlp gets the login through the environment, not its arguments', () {
      final (args, env) = NetworkProxy.hideCredentials(['--proxy', 'socks5h://u:p@h:1', '--', 'url'], {'A': 'b'});
      expect(args, ['--', 'url']);
      expect(env!['ALL_PROXY'], 'socks5h://u:p@h:1');
      expect(env['HTTPS_PROXY'], 'socks5h://u:p@h:1');
      expect(env['A'], 'b');
      final plain = ['--proxy', 'http://h:1', 'url'];
      final (same, none) = NetworkProxy.hideCredentials(plain, null);
      expect(same, plain);
      expect(none, isNull);
    });
  });

  test('skin files cannot leave the skin folder', () {
    for (final ok in ['a.png', 'img/a.png', 'fonts/My Font.ttf']) {
      expect(Skin.insideFolder(ok), isTrue, reason: ok);
    }
    for (final bad in ['', '../a.png', 'a/../../b', '/etc/passwd', r'..\a.png', r'C:\x.png', 'C:/x.png', 'a//b', './a']) {
      expect(Skin.insideFolder(bad), isFalse, reason: bad);
    }
  });

  test('a media host that resolves into the network is not public', () async {
    Future<List<InternetAddress>> lookup(String host) async => [InternetAddress(host == 'rebind.example' ? '192.168.1.5' : host == 'meta.example' ? '169.254.169.254' : '93.184.216.34')];
    expect(await resolvesToPublicAddress('rebind.example', lookup: lookup), isFalse);
    expect(await resolvesToPublicAddress('meta.example', lookup: lookup), isFalse);
    expect(await resolvesToPublicAddress('fine.example', lookup: lookup), isTrue);
    expect(await resolvesToPublicAddress('gone.example', lookup: (_) async => throw const SocketException('no')), isTrue);
  });
}

final _client = MockClient((_) async => http.Response('', 500));
