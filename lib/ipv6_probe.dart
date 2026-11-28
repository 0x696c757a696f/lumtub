import 'dart:async';
import 'dart:io';

/// Whether this network reaches YouTube over IPv6. yt-dlp (Python) tries
/// a host's addresses one after another, so where the computer has an
/// IPv6 address that goes nowhere every run first waits for a time-out.
class Ipv6Probe {
  /// True when a connection to YouTube over IPv6 opens within [timeout],
  /// false when it does not or there is no IPv6 address to try, null when
  /// even the name could not be looked up (offline).
  static Future<bool?> works(
      {String host = 'www.youtube.com',
      int port = 443,
      Duration timeout = const Duration(seconds: 2)}) async {
    final List<InternetAddress> addresses;
    try {
      addresses =
          await InternetAddress.lookup(host, type: InternetAddressType.IPv6).timeout(timeout);
    } on SocketException {
      return null;
    } on TimeoutException {
      return null;
    }
    if (addresses.isEmpty) return false;
    try {
      final socket = await Socket.connect(addresses.first, port, timeout: timeout);
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }
}
