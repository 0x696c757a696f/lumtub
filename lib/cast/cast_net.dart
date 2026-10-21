import 'dart:io';

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
