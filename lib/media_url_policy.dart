import 'dart:async';
import 'dart:io';

import 'network_proxy.dart' show isLocalHost;

/// Whether [url] may be handed to mpv as a stream address from a public
/// Piped or Invidious server: https only, and a host that is one of
/// [trustedHosts] (the server itself, its proxy) or YouTube's own. A server
/// is not trusted to point the player at IP addresses, localhost, `.local`
/// names or anything on the user's network.
bool isAllowedMediaUrl(String url, {Iterable<String> trustedHosts = const []}) {
  final uri = Uri.tryParse(url);
  if (uri == null || uri.scheme != 'https' || uri.userInfo.isNotEmpty) return false;
  final host = uri.host.toLowerCase();
  if (!_isPublicName(host)) return false;
  return trustedHosts.any((trusted) => trusted.toLowerCase() == host) || _isYoutubeHost(host);
}

/// A DNS name, not an IP literal in any spelling, localhost or `.local`.
bool _isPublicName(String host) {
  if (host.isEmpty || host == 'localhost' || host.endsWith('.localhost') || host.endsWith('.local')) return false;
  if (InternetAddress.tryParse(host) != null) return false;
  // 2130706433 and 0x7f.1 are addresses to some resolvers: the last label must be a name.
  final last = host.split('.').last;
  return RegExp(r'[a-z-]').hasMatch(last) && !last.startsWith('0x');
}

bool isYoutubeMediaHost(String host) => _isYoutubeHost(host);

bool _isYoutubeHost(String host) =>
    const ['googlevideo.com', 'youtube.com', 'ytimg.com'].any((domain) => host == domain || host.endsWith('.$domain'));

final _resolved = <String, ({DateTime at, bool public})>{};

/// Whether the host name [host] resolves to no loopback, private or
/// link-local address: a DNS name that points inside the user's network is
/// as bad as an IP literal. The answer is kept for five minutes; a name
/// that does not resolve counts as public, as the player cannot reach it
/// either. [lookup] is for tests.
Future<bool> resolvesToPublicAddress(String host, {Future<List<InternetAddress>> Function(String host)? lookup}) async {
  final key = host.toLowerCase();
  final known = _resolved[key];
  if (known != null && DateTime.now().difference(known.at) < const Duration(minutes: 5)) return known.public;
  var public = true;
  try {
    final found = await (lookup ?? InternetAddress.lookup)(key).timeout(const Duration(seconds: 4));
    public = !found.any((a) => isLocalHost(a.address) || a.isMulticast || a.address == '0.0.0.0' || a.address == '::');
  } catch (_) {}
  _resolved[key] = (at: DateTime.now(), public: public);
  return public;
}
