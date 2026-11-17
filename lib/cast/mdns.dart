import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../app_log.dart';
import 'cast_net.dart';
import 'cast_parse.dart';

// Minimal multicast DNS for finding Chromecasts and AirPlay receivers: one
// PTR question for the service, and the PTR, SRV, TXT, A and AAAA records
// that come back, read in the Rust core (cast_lan.rs).

const googleCastService = '_googlecast._tcp.local';
const airPlayService = '_airplay._tcp.local';

/// A DNS query packet asking for the PTR records of [service].
Uint8List mdnsQuery(String service) {
  final out = BytesBuilder();
  out.add([0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0]);
  for (final label in service.split('.')) {
    final bytes = utf8.encode(label);
    out.addByte(bytes.length);
    out.add(bytes);
  }
  out.add([0, 0, 12, 0, 1]);
  return out.toBytes();
}

/// A device found by mDNS.
class MdnsService {
  const MdnsService({required this.id, required this.name, required this.host, required this.port, this.txt = const {}});
  final String id;
  final String name;
  final InternetAddress host;
  final int port;

  /// Its TXT record, keys in lower case.
  final Map<String, String> txt;
}

/// Collects the records of mDNS replies; a service is complete once its
/// PTR, SRV, TXT and address records have all arrived, perhaps in several
/// packets.
class MdnsCollector {
  MdnsCollector({this.service = googleCastService});
  final String service;
  final _ptr = <String>{};
  final _srv = <String, (String, int)>{};
  final _txt = <String, Map<String, String>>{};
  final _addresses = <String, InternetAddress>{};

  /// Reads one packet in the core; what a malformed one holds before the
  /// damage is kept, the rest ignored.
  void add(Uint8List packet) {
    final Object? read;
    try {
      read = readInCore('lumtub_mdns_records', packet);
    } on FormatException {
      return;
    }
    if (read is! Map) return;
    final records = read;
    List<List<Object?>> rows(String key) => [for (final row in records[key] as List? ?? const []) if (row is List) row];
    for (final row in rows('ptr')) {
      if (row case [final String owner, final String target] when owner.toLowerCase() == service) _ptr.add(target);
    }
    for (final row in rows('srv')) {
      if (row case [final String name, final String target, final num port]) _srv[name] = (target, port.toInt());
    }
    for (final row in rows('txt')) {
      if (row case [final String name, final Map entries]) _txt[name] = {for (final MapEntry(:key, :value) in entries.entries) '$key': '$value'};
    }
    for (final row in rows('addresses')) {
      if (row case [final String name, final String text]) {
        final address = InternetAddress.tryParse(text);
        if (address == null) continue;
        // An IPv4 address wins over an IPv6 one for the same name.
        if (address.type == InternetAddressType.IPv4) {
          _addresses[name] = address;
        } else {
          _addresses.putIfAbsent(name, () => address);
        }
      }
    }
  }

  /// The services whose records are all known, an IPv4 address preferred.
  List<MdnsService> get services => [
        for (final instance in _ptr)
          if (_srv[instance] case (final target, final port)?)
            if (_addresses[target] case final address?)
              MdnsService(
                id: _txt[instance]?['id'] ?? instance,
                name: _txt[instance]?['fn'] ?? instance.split('.').first,
                host: address,
                port: port,
                txt: _txt[instance] ?? const {},
              ),
      ];
}

/// Asks the LAN for [service] for [timeout], emitting each device once.
/// The question goes out from a high port, so replies come back unicast and
/// nothing has to share port 5353 with the system's own mDNS.
Stream<MdnsService> discoverMdns({String service = googleCastService, Duration timeout = const Duration(seconds: 6)}) {
  final controller = StreamController<MdnsService>();
  final sockets = <RawDatagramSocket>[];
  final collector = MdnsCollector(service: service);
  final seen = <String>{};
  Timer? finish;
  Timer? repeat;

  void close() {
    finish?.cancel();
    repeat?.cancel();
    for (final s in sockets) {
      s.close();
    }
    if (!controller.isClosed) unawaited(controller.close());
  }

  controller.onListen = () async {
    final target = InternetAddress('224.0.0.251');
    final query = mdnsQuery(service);
    for (final address in await localIPv4Addresses()) {
      try {
        final socket = await RawDatagramSocket.bind(address, 0);
        sockets.add(socket);
        socket.listen((event) {
          if (event != RawSocketEvent.read) return;
          final packet = socket.receive();
          if (packet == null) return;
          collector.add(packet.data);
          for (final found in collector.services) {
            if (seen.add(found.id) && !controller.isClosed) controller.add(found);
          }
        });
      } on SocketException catch (e) {
        logWarn('mDNS discovery cannot use $address: ${e.message}');
      }
    }
    void ask() {
      for (final s in sockets) {
        try {
          s.send(query, target, 5353);
        } on SocketException {
          // That interface is not usable now.
        }
      }
    }

    ask();
    repeat = Timer.periodic(const Duration(seconds: 2), (_) => ask());
    finish = Timer(timeout, close);
  };
  controller.onCancel = close;
  return controller.stream;
}
