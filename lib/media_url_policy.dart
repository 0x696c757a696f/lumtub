import 'dart:io';

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

bool _isYoutubeHost(String host) =>
    const ['googlevideo.com', 'youtube.com', 'ytimg.com'].any((domain) => host == domain || host.endsWith('.$domain'));
