import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../app_log.dart';
import 'cast_net.dart';

// Minimal multicast DNS for finding Chromecasts: one PTR question for
// _googlecast._tcp.local and a reader for the PTR, SRV, TXT, A and AAAA
// records that come back.

const googleCastService = '_googlecast._tcp.local';

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

/// A Chromecast found by mDNS.
class MdnsService {
  const MdnsService({required this.id, required this.name, required this.host, required this.port});
  final String id;
  final String name;
  final InternetAddress host;
  final int port;
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

  /// Reads one packet; malformed ones are ignored.
  void add(Uint8List packet) {
    try {
      _read(ByteData.sublistView(packet), packet);
    } on RangeError {
      // Truncated packet.
    } on FormatException {
      // Bad name.
    }
  }

  void _read(ByteData data, Uint8List bytes) {
    var offset = 12;
    final questions = data.getUint16(4);
    final records = data.getUint16(6) + data.getUint16(8) + data.getUint16(10);
    for (var i = 0; i < questions; i++) {
      offset = _skipName(bytes, offset) + 4;
    }
    for (var i = 0; i < records; i++) {
      final (name, afterName) = _readName(bytes, offset);
      final type = data.getUint16(afterName);
      final length = data.getUint16(afterName + 8);
      final start = afterName + 10;
      final end = start + length;
      if (end > bytes.length) return;
      switch (type) {
        case 12 when name.toLowerCase() == service:
          _ptr.add(_readName(bytes, start).$1);
        case 33:
          _srv[name] = (_readName(bytes, start + 6).$1.toLowerCase(), data.getUint16(start + 4));
        case 16:
          _txt[name] = _parseTxt(bytes, start, end);
        case 1 when length == 4:
          _addresses[name.toLowerCase()] = InternetAddress.fromRawAddress(Uint8List.sublistView(bytes, start, end));
        case 28 when length == 16:
          _addresses.putIfAbsent(name.toLowerCase(), () => InternetAddress.fromRawAddress(Uint8List.sublistView(bytes, start, end)));
      }
      offset = end;
    }
  }

  Map<String, String> _parseTxt(Uint8List bytes, int start, int end) {
    final out = <String, String>{};
    var i = start;
    while (i < end) {
      final length = bytes[i++];
      if (i + length > end) break;
      final entry = utf8.decode(bytes.sublist(i, i + length), allowMalformed: true);
      i += length;
      final eq = entry.indexOf('=');
      if (eq > 0) out[entry.substring(0, eq).toLowerCase()] = entry.substring(eq + 1);
    }
    return out;
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
              ),
      ];

  static int _skipName(Uint8List bytes, int offset) {
    while (true) {
      final length = bytes[offset];
      if (length == 0) return offset + 1;
      if (length & 0xC0 == 0xC0) return offset + 2;
      offset += length + 1;
    }
  }

  /// A possibly compressed name, and the offset after it.
  static (String, int) _readName(Uint8List bytes, int offset) {
    final labels = <String>[];
    int? after;
    var hops = 0;
    while (true) {
      final length = bytes[offset];
      if (length == 0) {
        return (labels.join('.'), after ?? offset + 1);
      }
      if (length & 0xC0 == 0xC0) {
        after ??= offset + 2;
        offset = ((length & 0x3F) << 8) | bytes[offset + 1];
        if (++hops > 20) throw const FormatException('name loop');
        continue;
      }
      labels.add(utf8.decode(bytes.sublist(offset + 1, offset + 1 + length), allowMalformed: true));
      offset += length + 1;
    }
  }
}

/// Asks the LAN for Chromecasts for [timeout], emitting each service once.
/// The question goes out from a high port, so replies come back unicast and
/// nothing has to share port 5353 with the system's own mDNS.
Stream<MdnsService> discoverMdns({Duration timeout = const Duration(seconds: 6)}) {
  final controller = StreamController<MdnsService>();
  final sockets = <RawDatagramSocket>[];
  final collector = MdnsCollector();
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
    final query = mdnsQuery(googleCastService);
    for (final address in await localIPv4Addresses()) {
      try {
        final socket = await RawDatagramSocket.bind(address, 0);
        sockets.add(socket);
        socket.listen((event) {
          if (event != RawSocketEvent.read) return;
          final packet = socket.receive();
          if (packet == null) return;
          collector.add(packet.data);
          for (final service in collector.services) {
            if (seen.add(service.id) && !controller.isClosed) controller.add(service);
          }
        });
      } on SocketException catch (e) {
        logInfo('mDNS discovery cannot use $address: ${e.message}');
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
