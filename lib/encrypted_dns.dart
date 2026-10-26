import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

import 'l10n/l10n.dart';
import 'native_core.dart';

/// A DNS-over-HTTPS server for 加密 DNS. [bootstrap] are the addresses of
/// its host, so reaching it needs no DNS lookup of its own.
class DnsServer {
  const DnsServer(this.id, this.name, this.url, this.bootstrap);
  final String id;
  final String name;
  final String url;
  final List<String> bootstrap;

  static const custom = 'custom';

  static const presets = [
    DnsServer('cloudflare', 'Cloudflare', 'https://cloudflare-dns.com/dns-query', ['1.1.1.1', '1.0.0.1', '2606:4700:4700::1111']),
    DnsServer('google', 'Google', 'https://dns.google/dns-query', ['8.8.8.8', '8.8.4.4', '2001:4860:4860::8888']),
    DnsServer('quad9', 'Quad9', 'https://dns.quad9.net/dns-query', ['9.9.9.9', '149.112.112.112', '2620:fe::fe']),
  ];

  /// The server for setting [id] (`''` is off), with [customUrl] for [custom].
  static DnsServer? of(String id, String customUrl) {
    if (id == custom) {
      final url = normalize(customUrl);
      return url == null ? null : DnsServer(custom, url, url, const []);
    }
    for (final server in presets) {
      if (server.id == id) return server;
    }
    return null;
  }

  /// What the menu shows for setting [id].
  static String label(String id, String customUrl) => switch (id) {
        '' => tr('关闭（使用系统 DNS）'),
        custom => normalize(customUrl) == null ? tr('自定义') : tr('自定义：{0}', [normalize(customUrl)]),
        _ => of(id, customUrl)?.name ?? tr('关闭（使用系统 DNS）'),
      };

  /// An `https://` DoH address, `https://` added when missing and
  /// `/dns-query` when there is no path; null when it is not one.
  static String? normalize(String text) {
    var value = text.trim();
    if (value.isEmpty) return null;
    if (!value.contains('://')) value = 'https://$value';
    final uri = Uri.tryParse(value);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return null;
    return (uri.path.isEmpty || uri.path == '/' ? uri.replace(path: '/dns-query') : uri).toString();
  }

  Map<String, Object?> toJson() => {'url': url, 'bootstrap': bootstrap};
}

/// What [testDnsServer] found.
typedef DnsTest = ({bool ok, List<String> addresses, int milliseconds, String error});

/// Looks [host] up over [server] alone, without the system fallback, off the
/// UI thread.
Future<DnsTest> testDnsServer(DnsServer server, {String host = 'www.youtube.com'}) async {
  if (NativeCore.instance == null) return (ok: false, addresses: const <String>[], milliseconds: 0, error: tr('缺少原生核心'));
  final settings = jsonEncode(server.toJson());
  final answer = await Isolate.run(() {
    final core = NativeCore.instance!;
    final test = core.library.lookupFunction<Pointer<Utf8> Function(Pointer<Uint8>, Size, Pointer<Uint8>, Size), Pointer<Utf8> Function(Pointer<Uint8>, int, Pointer<Uint8>, int)>('lumtub_dns_test');
    return core.take(core.withText(settings, (s, sl) => core.withText(host, (h, hl) => test(s, sl, h, hl))));
  });
  final json = answer == null ? null : jsonDecode(answer) as Map<String, Object?>;
  if (json == null) return (ok: false, addresses: const <String>[], milliseconds: 0, error: tr('没有回应'));
  return (
    ok: json['ok'] == true,
    addresses: [for (final a in (json['addresses'] as List?) ?? const []) a.toString()],
    milliseconds: (json['ms'] as num?)?.toInt() ?? 0,
    error: json['error']?.toString() ?? '',
  );
}
