import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/cast/airplay.dart';
import 'package:lumtub/cast/cast_device.dart';
import 'package:lumtub/cast/mdns.dart';

MdnsService _service(Map<String, String> txt) => MdnsService(id: 'Living Room._airplay._tcp.local', name: 'Living Room', host: InternetAddress('192.168.1.30'), port: 7000, txt: txt);

void main() {
  test('reads the feature bits', () {
    expect(airPlayFeatures('0x5A7FFFF7,0x1E'), 0x1E5A7FFFF7);
    expect(airPlayFeatures('0x77'), 0x77);
    expect(airPlayFeatures(null), 0);
    expect(airPlayFeatures('junk'), 0);
  });

  test('tells AirPlay 2 receivers, PINs and speakers apart', () {
    final tv = AirPlayDevice.fromService(_service({'features': '0x4A7FDFD5,0xBC177FDE', 'flags': '0x244', 'deviceid': 'AA:BB:CC:DD:EE:FF', 'model': 'AppleTV11,1'}), null)!;
    expect(tv.id, 'airplay:AA:BB:CC:DD:EE:FF');
    expect(tv.name, 'Living Room');
    expect(tv.protocol, CastProtocol.airplay);
    expect(tv.v2, isTrue);
    expect(tv.needsPin, isTrue);
    final old = AirPlayDevice.fromService(_service({'features': '0x5A7FFFF7', 'sf': '0x4'}), null)!;
    expect(old.v2, isFalse);
    expect(old.needsPin, isFalse);
    expect(AirPlayDevice.fromService(_service({'features': '0x4A7FCA00,0xBC354BD0', 'model': 'AudioAccessory5,1'}), null), isNull);
    expect(AirPlayDevice.fromService(_service({'features': '0x4A7FDFD5,0xBC177FDE', 'model': 'Mac14,2'}), null), isNull);
  });

  test('asks the LAN for AirPlay', () {
    final q = mdnsQuery(airPlayService);
    expect(q.sublist(q.length - 5), [0, 0, 12, 0, 1]);
    expect(String.fromCharCodes(q.sublist(13, 21)), '_airplay');
  });

  // Run against a receiver given in LUMTUB_AIRPLAY_FAKE (PIN 1111), with
  // the core library in LUMTUB_CORE_DLL.
  final fake = Platform.environment['LUMTUB_AIRPLAY_FAKE'];
  test('pairs, plays and steers a receiver', () async {
    final parts = fake!.split(':');
    final pairings = AirPlayPairings();
    final device = AirPlayDevice(id: 'fake', name: 'Fake', address: InternetAddress(parts[0]), port: int.parse(parts[1]), features: 1 | 1 << 48, flags: 0x8, pairings: pairings);
    const media = CastMedia(url: 'http://127.0.0.1:1/x.m3u8', title: 'x', start: Duration(seconds: 5));
    await expectLater(device.load(media), throwsA(isA<AirPlayPinNeeded>()));
    var pairing = await device.startPairing();
    await expectLater(device.finishPairing(pairing, '0000'), throwsA(isA<CastException>()));
    pairing = await device.startPairing();
    await device.finishPairing(pairing, '1111');
    expect(await pairings.of('fake'), isNotNull);
    await device.load(media);
    expect((await device.status())!.state, CastState.playing);
    await device.pause();
    await device.seek(const Duration(seconds: 42));
    final status = (await device.status())!;
    expect(status.state, CastState.paused);
    expect(status.position, const Duration(seconds: 42));
    expect(status.duration, const Duration(seconds: 100));
    await device.stop();
    expect(await device.status(), isNull);
  }, skip: fake == null);
}
