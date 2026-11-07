import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'l10n/l10n.dart';
import 'native_core.dart';

/// Where Lumtub sends its network traffic: yt-dlp, libmpv's video streams
/// and the app's own requests all go the same way.
enum ProxyMode {
  /// The proxy set in Windows (as Clash, v2rayN and similar tools set it),
  /// or none when Windows has none.
  system('Follow system (recommended)'),
  off('No proxy'),
  custom('Enter manually');

  const ProxyMode(this._label);
  final String _label;
  String get label => tr(_label);
}

/// A proxy address as `http://host:port` or `socks5://[user:pass@]host:port`,
/// or null for a direct connection. yt-dlp takes either kind itself; libmpv
/// and dart:io only speak HTTP proxies, so a SOCKS one reaches them through
/// the local `SocksBridge`.
class NetworkProxy {
  const NetworkProxy(this.url);
  final String? url;

  static const direct = NetworkProxy(null);

  bool get isHttp => url != null && url!.startsWith('http://');
  bool get isSocks => url != null && !isHttp;

  /// [url] without the password, for logs.
  String? get redacted => url?.replaceFirst(RegExp(r'//[^@/]*@'), '//');

  /// yt-dlp's `--proxy` value for [mode]: an empty string forces a direct
  /// connection, null leaves yt-dlp to find the Windows proxy itself.
  String? ytDlpValue(ProxyMode mode) => mode == ProxyMode.off ? '' : url;

  /// `host:port` for dart:io's `PROXY` rule.
  String? get hostPort {
    final uri = url == null ? null : Uri.tryParse(url!);
    return uri == null || uri.host.isEmpty || !uri.hasPort ? null : '${uri.host}:${uri.port}';
  }

  /// Normalises what a person typed, such as `127.0.0.1:7890` or
  /// `socks5://127.0.0.1:7891`, or returns null when it is not an address.
  static String? normalize(String text) {
    var value = text.trim();
    if (value.isEmpty) return null;
    if (!value.contains('://')) value = 'http://$value';
    final uri = Uri.tryParse(value);
    if (uri == null || uri.host.isEmpty || !uri.hasPort || uri.port <= 0) return null;
    if (!{'http', 'socks5', 'socks5h', 'socks4', 'socks4a'}.contains(uri.scheme)) return null;
    final login = uri.scheme.startsWith('socks') && uri.userInfo.isNotEmpty ? '${uri.userInfo}@' : '';
    return '${uri.scheme}://$login${uri.host.contains(':') ? '[${uri.host}]' : uri.host}:${uri.port}';
  }

  /// The proxy in Windows' `ProxyServer` value: either one address for
  /// every protocol or `http=…;https=…;socks=…`.
  static String? parseWindows(String server) {
    final parts = server.split(';').map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return null;
    if (!parts.any((p) => p.contains('='))) return normalize(parts.first);
    final byScheme = {
      for (final part in parts)
        if (part.contains('=')) part.substring(0, part.indexOf('=')).toLowerCase(): part.substring(part.indexOf('=') + 1),
    };
    final http = byScheme['https'] ?? byScheme['http'];
    if (http != null) return normalize(http.contains('://') ? http : 'http://$http');
    final socks = byScheme['socks'];
    return socks == null ? null : normalize(socks.contains('://') ? socks : 'socks5://$socks');
  }

  /// The Linux proxy: the environment's https_proxy or all_proxy, else
  /// GNOME's proxy setting (gsettings), which other desktops often share.
  static Future<NetworkProxy> linux({Map<String, String>? environment, Future<String?> Function(String key)? gsettings, Future<String?> Function(String url)? fetchPac}) async {
    final env = environment ?? Platform.environment;
    for (final name in ['https_proxy', 'HTTPS_PROXY', 'http_proxy', 'HTTP_PROXY', 'all_proxy', 'ALL_PROXY']) {
      final value = env[name]?.trim() ?? '';
      if (value.isNotEmpty) return NetworkProxy(normalize(value.contains('://') ? value : 'http://$value'));
    }
    final read = gsettings ?? _gsettings;
    final mode = await read('org.gnome.system.proxy mode');
    if (mode == 'auto') return pac(await read('org.gnome.system.proxy autoconfig-url') ?? '', fetch: fetchPac);
    if (mode != 'manual') return direct;
    for (final (schema, scheme) in [('https', 'http'), ('http', 'http'), ('socks', 'socks5')]) {
      final host = await read('org.gnome.system.proxy.$schema host') ?? '';
      final port = int.tryParse(await read('org.gnome.system.proxy.$schema port') ?? '') ?? 0;
      if (host.isNotEmpty && port > 0) return NetworkProxy(normalize('$scheme://$host:$port'));
    }
    return direct;
  }

  /// The macOS proxy of the active network service, as `scutil --proxy`
  /// prints it (the setting in System Settings › Network › Proxies).
  static Future<NetworkProxy> mac({Future<String?> Function()? scutil, Future<String?> Function(String url)? fetchPac}) async {
    final text = await (scutil ?? _scutil)() ?? '';
    final values = {
      for (final match in RegExp(r'^\s*(\w+)\s*:\s*(\S+)\s*$', multiLine: true).allMatches(text)) match.group(1)!: match.group(2)!,
    };
    for (final (key, scheme) in [('HTTPS', 'http'), ('HTTP', 'http'), ('SOCKS', 'socks5')]) {
      if (values['${key}Enable'] != '1') continue;
      final host = values['${key}Proxy'] ?? '';
      final port = int.tryParse(values['${key}Port'] ?? '') ?? 0;
      if (host.isNotEmpty && port > 0) return NetworkProxy(normalize('$scheme://$host:$port'));
    }
    if (values['ProxyAutoConfigEnable'] == '1') return pac(values['ProxyAutoConfigURLString'] ?? '', fetch: fetchPac);
    return direct;
  }

  /// The proxy that the proxy auto-config (PAC) script at [url] names, as
  /// proxy tools serve one in their PAC mode (see `native/lumtub_core/src/pac.rs`);
  /// direct when it names none or cannot be read. [fetch] answers the
  /// proxy for a script address, for tests.
  static Future<NetworkProxy> pac(String url, {Future<String?> Function(String url)? fetch}) async {
    if (url.trim().isEmpty) return direct;
    final found = await (fetch ?? _pacProxy)(url.trim());
    return found == null ? direct : NetworkProxy(normalize(found));
  }

  static Future<String?> _pacProxy(String url) async {
    if (NativeCore.instance == null) return null;
    try {
      final answer = await Isolate.run(() {
        final core = NativeCore.instance!;
        return core.take(core.withText(url, core.pacProxy));
      });
      final json = jsonDecode(answer ?? 'null');
      return json is Map ? json['proxy'] as String? : null;
    } catch (_) {
      return null;
    }
  }

  static Future<String?> _scutil() async {
    try {
      final result = await Process.run('/usr/sbin/scutil', ['--proxy']).timeout(const Duration(seconds: 3));
      return result.exitCode == 0 ? result.stdout.toString() : null;
    } catch (_) {
      return null;
    }
  }

  static Future<String?> _gsettings(String key) async {
    try {
      final result = await Process.run('gsettings', ['get', ...key.split(' ')]).timeout(const Duration(seconds: 3));
      if (result.exitCode != 0) return null;
      final text = result.stdout.toString().trim();
      return text.startsWith("'") && text.endsWith("'") && text.length >= 2 ? text.substring(1, text.length - 1) : text;
    } catch (_) {
      return null;
    }
  }

  /// The Windows proxy, read from the registry as the browsers read it.
  static Future<NetworkProxy> windows() async {
    if (!Platform.isWindows) return direct;
    final core = NativeCore.instance;
    if (core != null) {
      try {
        final setting = jsonDecode(core.take(core.systemProxy()) ?? 'null');
        if (setting is Map && setting['enabled'] is bool) {
          final server = '${setting['server'] ?? ''}';
          if (setting['enabled'] == true && server.isNotEmpty) return NetworkProxy(parseWindows(server));
          return await pac('${setting['pac'] ?? ''}');
        }
      } catch (_) {
        // Read it with reg.exe below.
      }
    }
    try {
      const key = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings';
      final enabled = await Process.run('reg', ['query', key, '/v', 'ProxyEnable']).timeout(const Duration(seconds: 5));
      if (!RegExp(r'ProxyEnable\s+REG_DWORD\s+0x0*1\b').hasMatch(enabled.stdout.toString())) {
        final script = await Process.run('reg', ['query', key, '/v', 'AutoConfigURL']).timeout(const Duration(seconds: 5));
        return await pac(RegExp(r'AutoConfigURL\s+REG_SZ\s+(.+)').firstMatch(script.stdout.toString())?.group(1) ?? '');
      }
      final server = await Process.run('reg', ['query', key, '/v', 'ProxyServer']).timeout(const Duration(seconds: 5));
      final match = RegExp(r'ProxyServer\s+REG_SZ\s+(.+)').firstMatch(server.stdout.toString());
      return NetworkProxy(match == null ? null : parseWindows(match.group(1)!.trim()));
    } catch (_) {
      return direct;
    }
  }

  static Future<NetworkProxy> resolve(ProxyMode mode, String address) async {
    final found = switch (mode) {
      ProxyMode.system => Platform.isLinux
          ? await linux()
          : Platform.isMacOS
              ? await mac()
              : await windows(),
      ProxyMode.off => direct,
      ProxyMode.custom => NetworkProxy(normalize(address)),
    };
    return NetworkProxy(remoteDns(found.url));
  }

  /// [url] with a SOCKS proxy asked to look host names up itself, as
  /// browsers do: a name looked up here may get a tampered answer, or none
  /// for a host only the proxy can reach.
  static String? remoteDns(String? url) {
    if (url == null) return null;
    if (url.startsWith('socks5://')) return 'socks5h://${url.substring(9)}';
    if (url.startsWith('socks4://')) return 'socks4a://${url.substring(9)}';
    return url;
  }
}

/// The overrides main installs; the controller updates their route.
final appHttpOverrides = ProxyHttpOverrides();

/// Sends every dart:io connection the app makes (thumbnails, feeds, posts,
/// updates) through [endpoint], an HTTP proxy that is either the user's own
/// or the local `SocksBridge`. Without one the connection is direct, and the
/// proxy environment variables are read only when [useEnvironment] is set.
class ProxyHttpOverrides extends HttpOverrides {
  /// `host:port` of the HTTP proxy, or null for direct.
  String? endpoint;
  bool useEnvironment = false;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.findProxy = route;
    return client;
  }

  /// dart:io's proxy rule for [uri]; [environment] is for tests.
  String route(Uri uri, {Map<String, String>? environment}) {
    // This PC and devices on the home network (DLNA, Chromecast) are never
    // behind the proxy.
    if (isLocalHost(uri.host)) return 'DIRECT';
    if (endpoint != null) return 'PROXY $endpoint';
    return useEnvironment ? HttpClient.findProxyFromEnvironment(uri, environment: environment) : 'DIRECT';
  }
}

/// Whether [host] is this PC or an address on the local network: loopback,
/// private (10/8, 172.16/12, 192.168/16, fc00::/7), link-local or `.local`.
bool isLocalHost(String host) {
  final h = host.toLowerCase();
  if (h == 'localhost' || h.endsWith('.local')) return true;
  final ip = InternetAddress.tryParse(h.startsWith('[') ? h.substring(1, h.length - 1) : h);
  if (ip == null) return false;
  if (ip.isLoopback || ip.isLinkLocal) return true;
  final b = ip.rawAddress;
  if (ip.type == InternetAddressType.IPv4) {
    return b[0] == 10 || (b[0] == 172 && b[1] >= 16 && b[1] < 32) || (b[0] == 192 && b[1] == 168);
  }
  return (b[0] & 0xfe) == 0xfc;
}
