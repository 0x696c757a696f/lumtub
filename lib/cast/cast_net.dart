import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// The addresses of this computer's IPv4 interfaces that can reach a LAN,
/// so a search goes out on each of them (a VPN or virtual adapter alone
/// would otherwise take the multicast).
Future<List<InternetAddress>> localIPv4Addresses() async {
  try {
    final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
    final found = <InternetAddress>[
      for (final i in interfaces)
        for (final a in i.addresses)
          if (!a.isLoopback && !a.isLinkLocal) a,
    ];
    if (found.isNotEmpty) return found;
  } on SocketException {
    // Falls through to the default route.
  }
  return [InternetAddress.anyIPv4];
}

/// A reply from a device on the LAN as text, at most [limit] bytes: any
/// device on the network can answer, so a longer reply is not read at all.
Future<String> readDeviceReply(HttpClientResponse response, {int limit = 512 * 1024}) async {
  final bytes = BytesBuilder(copy: false);
  await for (final chunk in response) {
    if (bytes.length + chunk.length > limit) throw const HttpException('The reply is too long');
    bytes.add(chunk);
  }
  return utf8.decode(bytes.takeBytes(), allowMalformed: true);
}
