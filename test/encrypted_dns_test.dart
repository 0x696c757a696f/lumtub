import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/encrypted_dns.dart';
import 'package:lumtub/native_core.dart';
import 'package:lumtub/player_settings.dart';

void main() {
  test('DoH addresses are normalized', () {
    expect(DnsServer.normalize('dns.example.com'), 'https://dns.example.com/dns-query');
    expect(DnsServer.normalize(' https://dns.example.com/ '), 'https://dns.example.com/dns-query');
    expect(DnsServer.normalize('https://dns.example.com/resolve?x=1'), 'https://dns.example.com/resolve?x=1');
    expect(DnsServer.normalize('http://dns.example.com/dns-query'), isNull);
    expect(DnsServer.normalize(''), isNull);
  });

  test('settings pick a server or none', () {
    expect(DnsServer.of('', ''), isNull);
    expect(DnsServer.of('cloudflare', '')!.bootstrap, contains('1.1.1.1'));
    expect(DnsServer.of('custom', 'dns.example.com')!.url, 'https://dns.example.com/dns-query');
    expect(DnsServer.of('custom', 'nope://'), isNull);
    expect(DnsServer.of('gone', ''), isNull);
    final settings = PlayerSettings.fromJson(const PlayerSettings(dnsServer: 'custom', dnsCustomUrl: 'https://dns.example.com/dns-query').toJson());
    expect((settings.dnsServer, settings.dnsCustomUrl), ('custom', 'https://dns.example.com/dns-query'));
    expect(const PlayerSettings().dnsServer, '');
  });

  test('a server that cannot be reached fails the test', () async {
    final result = await testDnsServer(const DnsServer('custom', 'x', 'https://127.0.0.1:9/dns-query', []));
    expect(result.ok, isFalse);
    expect(result.error, isNotEmpty);
  }, skip: NativeCore.instance == null ? 'needs LUMTUB_CORE_DLL' : false);
}
