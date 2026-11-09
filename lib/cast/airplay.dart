import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

import '../native_core.dart';
import '../secure_store.dart';
import 'cast_device.dart';
import 'mdns.dart';

/// One request to lumtub_core's AirPlay sender, on another isolate since it
/// blocks while the device answers; a refusal is thrown as [CastException].
Future<Map<String, dynamic>> airPlayAsk(Map<String, Object?> ask) async {
  final text = jsonEncode(ask);
  final answer = jsonDecode(await Isolate.run(() => _airPlayCall(text)));
  if (answer is! Map<String, dynamic>) throw const CastException('no answer');
  if (answer['error'] case final String error) throw CastException(error);
  return answer;
}

String _airPlayCall(String text) {
  final core = NativeCore.instance;
  if (core == null) return '{"error":"no lumtub_core"}';
  final call = core.library.lookupFunction<Pointer<Utf8> Function(Pointer<Uint8>, Size), Pointer<Utf8> Function(Pointer<Uint8>, int)>('lumtub_airplay');
  return core.take(core.withText(text, call)) ?? '{"error":"no answer"}';
}

/// The feature bits an AirPlay receiver announces, written "0xLOW,0xHIGH".
int airPlayFeatures(String? text) {
  if (text == null) return 0;
  int part(String s) => int.tryParse(s.trim().replaceFirst(RegExp('^0[xX]'), ''), radix: 16) ?? 0;
  final parts = text.split(',');
  return part(parts[0]) | (parts.length > 1 ? part(parts[1]) << 32 : 0);
}

/// Thrown when the device wants the PIN it shows before it plays.
class AirPlayPinNeeded extends CastException {
  const AirPlayPinNeeded() : super('PIN needed');
}

/// The keys kept from pairing with each receiver, encrypted on disk.
class AirPlayPairings {
  AirPlayPairings([this.file]);
  SecureJsonFile? file;
  Map<String, dynamic>? _all;

  Future<Map<String, dynamic>> _read() async => _all ??= await file?.read() ?? <String, dynamic>{};

  Future<String?> of(String id) async => (await _read())[id] as String?;

  Future<void> put(String id, String credentials) async {
    final all = await _read();
    all[id] = credentials;
    await file?.write(all);
  }

  Future<void> forget(String id) async {
    final all = await _read();
    if (all.remove(id) != null) await file?.write(all);
  }
}

/// An Apple TV, or a TV with AirPlay, that plays the address it is given.
class AirPlayDevice implements CastDevice {
  AirPlayDevice({required this.id, required this.name, required this.address, required this.port, required this.features, this.flags = 0, this.pairings});

  /// A receiver found by mDNS, or null for one that plays no video.
  static AirPlayDevice? fromService(MdnsService service, AirPlayPairings? pairings) {
    final features = airPlayFeatures(service.txt['features'] ?? service.txt['ft']);
    if (features & 1 == 0 || RegExp(r'^Mac\d+,\d+$').hasMatch(service.txt['model'] ?? '')) return null;
    return AirPlayDevice(
      id: 'airplay:${service.txt['deviceid'] ?? service.id}',
      name: service.name,
      address: service.host,
      port: service.port,
      features: features,
      flags: int.tryParse((service.txt['sf'] ?? service.txt['flags'] ?? '0').replaceFirst(RegExp('^0[xX]'), ''), radix: 16) ?? 0,
      pairings: pairings,
    );
  }

  @override
  final String id;
  @override
  final String name;
  final InternetAddress address;
  @override
  final int port;
  final int features;
  final int flags;
  final AirPlayPairings? pairings;
  int? _session;
  var _ready = false;

  @override
  CastProtocol get protocol => CastProtocol.airplay;
  @override
  String get host => address.address;

  /// AirPlay 2: unified media control or HomeKit pairing announced.
  bool get v2 => features & (1 << 38 | 1 << 48) != 0;

  /// Whether the device asks for the PIN it shows.
  bool get needsPin => flags & (0x8 | 0x200) != 0;

  String get _target => address.type == InternetAddressType.IPv6 ? '[${address.address}]:$port' : '${address.address}:$port';

  /// Asks the device to show a PIN; the pairing to finish with it.
  Future<int> startPairing() async => (await airPlayAsk({'op': 'pairStart', 'address': _target}))['pairing'] as int;

  /// Pairs with the PIN the user read off the TV and keeps the keys.
  Future<void> finishPairing(int pairing, String pin) async {
    final answer = await airPlayAsk({'op': 'pairFinish', 'pairing': pairing, 'pin': pin});
    await pairings?.put(id, answer['credentials'] as String);
  }

  @override
  Future<void> load(CastMedia media) async {
    final credentials = await pairings?.of(id);
    if (credentials == null && needsPin) throw const AirPlayPinNeeded();
    try {
      final answer = await airPlayAsk({
        'op': 'play',
        'address': _target,
        if (credentials != null) 'credentials': credentials,
        'transient': credentials == null && v2,
        'v2': v2,
        'url': media.url,
        'position': media.start.inMilliseconds / 1000,
      });
      _session = answer['session'] as int;
      _ready = false;
    } on CastException catch (e) {
      if (credentials != null && e.message.contains('pair again')) {
        await pairings?.forget(id);
        throw const AirPlayPinNeeded();
      }
      if (credentials == null && RegExp('needs a PIN|needs pairing|refused').hasMatch(e.message)) throw const AirPlayPinNeeded();
      rethrow;
    }
  }

  Future<void> _steer(Map<String, Object?> ask) async {
    final session = _session;
    if (session == null) throw const CastException('not playing');
    await airPlayAsk({...ask, 'session': session});
  }

  @override
  Future<void> play() => _steer({'op': 'rate', 'value': 1.0});
  @override
  Future<void> pause() => _steer({'op': 'rate', 'value': 0.0});
  @override
  Future<void> seek(Duration position) => _steer({'op': 'seek', 'seconds': position.inMilliseconds / 1000});

  @override
  Future<CastStatus?> status() async {
    final session = _session;
    if (session == null) return null;
    try {
      final s = await airPlayAsk({'op': 'status', 'session': session});
      final duration = (s['duration'] as num?)?.toDouble() ?? 0;
      final ready = s['ready'] == true;
      // After the end the device reports nothing about the item any more.
      final ended = _ready && !ready && duration == 0;
      _ready |= ready;
      final state = ended || s['error'] != null
          ? CastState.stopped
          : !ready
              ? CastState.loading
              : ((s['rate'] as num?) ?? 0) > 0
                  ? CastState.playing
                  : CastState.paused;
      Duration time(String key) => Duration(milliseconds: (((s[key] as num?) ?? 0) * 1000).round());
      return CastStatus(state: state, position: time('position'), duration: time('duration'));
    } on CastException {
      return null;
    }
  }

  @override
  Future<void> stop() => close();

  /// Ends the session; the device stops once its connection is gone.
  @override
  Future<void> close() async {
    final session = _session;
    _session = null;
    if (session != null) await airPlayAsk({'op': 'stop', 'session': session});
  }
}

/// Searches the LAN for AirPlay receivers that play video.
Stream<CastDevice> discoverAirPlay({Duration timeout = const Duration(seconds: 6), AirPlayPairings? pairings}) =>
    discoverMdns(service: airPlayService, timeout: timeout).map((s) => AirPlayDevice.fromService(s, pairings)).where((d) => d != null).cast<CastDevice>();
