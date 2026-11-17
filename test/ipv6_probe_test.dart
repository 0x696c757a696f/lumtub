import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/ipv6_probe.dart';
import 'package:lumtub/player_settings.dart';

void main() {
  test('a name that cannot be looked up gives no answer', () async {
    expect(await Ipv6Probe.works(host: 'nothing-here.invalid'), isNull);
  });

  test('a listening IPv6 port is reached', () async {
    final ServerSocket server;
    try {
      server = await ServerSocket.bind(InternetAddress.loopbackIPv6, 0);
    } on SocketException {
      markTestSkipped('no IPv6 loopback here');
      return;
    }
    addTearDown(server.close);
    expect(await Ipv6Probe.works(host: '::1', port: server.port), isTrue);
    final port = server.port;
    await server.close();
    expect(await Ipv6Probe.works(host: '::1', port: port), isFalse);
  });

  test('the IPv4 setting is kept and defaults to automatic', () {
    expect(PlayerSettings.fromJson(const {}).ipVersion, 'auto');
    expect(PlayerSettings.fromJson({'ipVersion': 'nonsense'}).ipVersion, 'auto');
    for (final mode in ['auto', 'ipv4', 'any']) {
      expect(PlayerSettings.fromJson(const PlayerSettings().copyWith(ipVersion: mode).toJson()).ipVersion, mode);
    }
  });
}
