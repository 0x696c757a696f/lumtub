import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../app_log.dart';
import 'cast_device.dart';
import 'mdns.dart';

// Google Cast (CASTV2) sender: a TLS connection to port 8009 carrying
// length-prefixed protobuf CastMessages whose payloads are JSON. Only the
// five CastMessage fields in use are encoded by hand.

const castConnectionNamespace = 'urn:x-cast:com.google.cast.tp.connection';
const castHeartbeatNamespace = 'urn:x-cast:com.google.cast.tp.heartbeat';
const castReceiverNamespace = 'urn:x-cast:com.google.cast.receiver';
const castMediaNamespace = 'urn:x-cast:com.google.cast.media';

/// The Default Media Receiver, which plays any address it is given.
const defaultMediaReceiverId = 'CC1AD845';

/// One CastMessage with a string payload.
class CastMessage {
  const CastMessage({required this.source, required this.destination, required this.namespace, required this.payload});
  final String source;
  final String destination;
  final String namespace;
  final String payload;

  Map<String, dynamic>? get json {
    try {
      final data = jsonDecode(payload);
      return data is Map<String, dynamic> ? data : null;
    } on FormatException {
      return null;
    }
  }
}

void _varint(BytesBuilder out, int value) {
  while (value > 0x7F) {
    out.addByte((value & 0x7F) | 0x80);
    value >>= 7;
  }
  out.addByte(value);
}

void _stringField(BytesBuilder out, int field, String value) {
  final bytes = utf8.encode(value);
  _varint(out, (field << 3) | 2);
  _varint(out, bytes.length);
  out.add(bytes);
}

/// The protobuf encoding of [message]: protocol_version CASTV2_1_0,
/// source_id, destination_id, namespace, payload_type STRING and
/// payload_utf8.
Uint8List encodeCastMessage(CastMessage message) {
  final out = BytesBuilder();
  _varint(out, 1 << 3);
  _varint(out, 0);
  _stringField(out, 2, message.source);
  _stringField(out, 3, message.destination);
  _stringField(out, 4, message.namespace);
  _varint(out, 5 << 3);
  _varint(out, 0);
  _stringField(out, 6, message.payload);
  return out.toBytes();
}

/// [message] with the 4-byte big-endian length the socket carries.
Uint8List frameCastMessage(CastMessage message) {
  final body = encodeCastMessage(message);
  return (BytesBuilder()
        ..add((ByteData(4)..setUint32(0, body.length)).buffer.asUint8List())
        ..add(body))
      .toBytes();
}

/// Reads a CastMessage; fields it does not use are skipped. Throws
/// [FormatException] on a malformed one.
CastMessage decodeCastMessage(Uint8List bytes) {
  var i = 0;
  int varint() {
    var value = 0;
    var shift = 0;
    while (true) {
      if (i >= bytes.length || shift > 63) throw const FormatException('bad varint');
      final b = bytes[i++];
      value |= (b & 0x7F) << shift;
      if (b & 0x80 == 0) return value;
      shift += 7;
    }
  }

  final strings = <int, String>{};
  while (i < bytes.length) {
    final tag = varint();
    switch (tag & 7) {
      case 0:
        varint();
      case 2:
        final length = varint();
        if (i + length > bytes.length) throw const FormatException('truncated field');
        if (tag >> 3 != 7) strings[tag >> 3] = utf8.decode(bytes.sublist(i, i + length), allowMalformed: true);
        i += length;
      case 1:
        i += 8;
      case 5:
        i += 4;
      default:
        throw const FormatException('bad wire type');
    }
  }
  return CastMessage(source: strings[2] ?? '', destination: strings[3] ?? '', namespace: strings[4] ?? '', payload: strings[6] ?? '');
}

/// Splits the bytes of a socket into the messages they frame.
class CastFrameReader {
  var _bytes = Uint8List(0);

  List<CastMessage> add(List<int> data) {
    _bytes = Uint8List.fromList([..._bytes, ...data]);
    final out = <CastMessage>[];
    while (_bytes.length >= 4) {
      final length = ByteData.sublistView(_bytes).getUint32(0);
      if (length > 1 << 20) throw const FormatException('message too long');
      if (_bytes.length < 4 + length) break;
      out.add(decodeCastMessage(Uint8List.sublistView(_bytes, 4, 4 + length)));
      _bytes = Uint8List.sublistView(_bytes, 4 + length);
    }
    return out;
  }
}

/// The receiver app named [appId] in a RECEIVER_STATUS payload.
({String transportId, String sessionId})? parseReceiverApp(Map<String, dynamic> json, String appId) {
  final status = json['status'];
  final apps = status is Map ? status['applications'] : null;
  if (apps is! List) return null;
  for (final app in apps.whereType<Map>()) {
    if (app['appId'] == appId && app['transportId'] is String && app['sessionId'] is String) {
      return (transportId: app['transportId'] as String, sessionId: app['sessionId'] as String);
    }
  }
  return null;
}

/// The first entry of a MEDIA_STATUS payload; null when it lists none.
class MediaStatus {
  const MediaStatus({required this.sessionId, required this.status});
  final int sessionId;
  final CastStatus status;
}

MediaStatus? parseMediaStatus(Map<String, dynamic> json) {
  final list = json['status'];
  if (list is! List || list.isEmpty || list.first is! Map) return null;
  final entry = list.first as Map;
  final state = switch (entry['playerState']) {
    'PLAYING' => CastState.playing,
    'PAUSED' => CastState.paused,
    'BUFFERING' => CastState.loading,
    _ => CastState.stopped,
  };
  Duration seconds(Object? value) => value is num ? Duration(milliseconds: (value * 1000).round()) : Duration.zero;
  final media = entry['media'];
  return MediaStatus(
    sessionId: (entry['mediaSessionId'] as num?)?.toInt() ?? 0,
    status: CastStatus(state: state, position: seconds(entry['currentTime']), duration: media is Map ? seconds(media['duration']) : Duration.zero),
  );
}

/// Connects to a Chromecast; replaceable in tests.
typedef CastConnector = Future<Socket> Function(InternetAddress host, int port);

Future<Socket> _secureConnect(InternetAddress host, int port) =>
    // Chromecasts present a self-signed certificate; it is accepted for
    // this connection only.
    SecureSocket.connect(host, port, onBadCertificate: (_) => true, timeout: const Duration(seconds: 6));

/// A Chromecast, driven through the Default Media Receiver.
class ChromecastDevice implements CastDevice {
  ChromecastDevice({required this.id, required this.name, required this.host, this.port = 8009, CastConnector? connector}) : _connector = connector ?? _secureConnect;

  factory ChromecastDevice.fromService(MdnsService service) => ChromecastDevice(id: service.id, name: service.name, host: service.host, port: service.port);

  @override
  final String id;
  @override
  final String name;
  @override
  CastProtocol get protocol => CastProtocol.chromecast;
  final InternetAddress host;
  final int port;
  final CastConnector _connector;

  static const _sender = 'sender-0';
  Socket? _socket;
  Timer? _heartbeat;
  final _reader = CastFrameReader();
  final _pending = <int, Completer<Map<String, dynamic>>>{};
  Completer<({String transportId, String sessionId})>? _launch;
  var _requestId = 0;
  String? _transportId;
  String? _sessionId;
  int? _mediaSessionId;
  var _duration = Duration.zero;

  Future<void> _connect() async {
    if (_socket != null) return;
    final Socket socket;
    try {
      socket = await _connector(host, port);
    } on SocketException catch (e) {
      throw CastException(e.message);
    } on TimeoutException {
      throw const CastException('timed out');
    } on HandshakeException catch (e) {
      throw CastException(e.message);
    }
    _socket = socket;
    socket.listen(_onData, onError: (_) => _lost(), onDone: _lost, cancelOnError: true);
    _send(castConnectionNamespace, 'receiver-0', {'type': 'CONNECT'});
    _heartbeat = Timer.periodic(const Duration(seconds: 5), (_) => _send(castHeartbeatNamespace, 'receiver-0', {'type': 'PING'}));
  }

  void _lost() {
    _heartbeat?.cancel();
    _socket = null;
    _transportId = _sessionId = _mediaSessionId = null;
    for (final waiting in _pending.values) {
      if (!waiting.isCompleted) waiting.completeError(const CastException('connection lost'));
    }
    _pending.clear();
    if (_launch case final launch? when !launch.isCompleted) launch.completeError(const CastException('connection lost'));
  }

  void _onData(List<int> data) {
    final List<CastMessage> messages;
    try {
      messages = _reader.add(data);
    } on FormatException {
      _socket?.destroy();
      _lost();
      return;
    }
    for (final message in messages) {
      final json = message.json;
      if (json == null) continue;
      switch (json['type']) {
        case 'PING':
          _send(castHeartbeatNamespace, message.source, {'type': 'PONG'});
        case 'RECEIVER_STATUS':
          if (parseReceiverApp(json, defaultMediaReceiverId) case final app? when _launch?.isCompleted == false) _launch!.complete(app);
        case 'LAUNCH_ERROR':
          if (_launch case final launch? when !launch.isCompleted) launch.completeError(CastException('${json['reason'] ?? 'launch failed'}'));
        case 'MEDIA_STATUS':
          if (parseMediaStatus(json) case final media? when media.sessionId != 0) _mediaSessionId = media.sessionId;
      }
      final id = json['requestId'];
      if (id is int && id != 0) _pending.remove(id)?.complete(json);
    }
  }

  void _send(String namespace, String destination, Map<String, Object?> payload) {
    _socket?.add(frameCastMessage(CastMessage(source: _sender, destination: destination, namespace: namespace, payload: jsonEncode(payload))));
  }

  Future<Map<String, dynamic>> _request(String namespace, String destination, Map<String, Object?> payload, {Duration timeout = const Duration(seconds: 10)}) {
    if (_socket == null) return Future.error(const CastException('connection lost'));
    final id = ++_requestId;
    final completer = _pending[id] = Completer();
    _send(namespace, destination, {...payload, 'requestId': id});
    return completer.future.timeout(timeout, onTimeout: () {
      _pending.remove(id);
      throw const CastException('timed out');
    });
  }

  @override
  Future<void> load(CastMedia media) async {
    await _connect();
    try {
      final launch = _launch = Completer();
      _send(castReceiverNamespace, 'receiver-0', {'type': 'LAUNCH', 'appId': defaultMediaReceiverId, 'requestId': ++_requestId});
      final app = await launch.future.timeout(const Duration(seconds: 15), onTimeout: () => throw const CastException('timed out'));
      _transportId = app.transportId;
      _sessionId = app.sessionId;
      _send(castConnectionNamespace, app.transportId, {'type': 'CONNECT'});
      final reply = await _request(castMediaNamespace, app.transportId, {
        'type': 'LOAD',
        'autoplay': true,
        'currentTime': media.start.inMilliseconds / 1000,
        'media': {
          'contentId': media.url,
          'contentType': media.mime,
          'streamType': 'BUFFERED',
          'metadata': {'metadataType': 0, 'title': media.title},
        },
      }, timeout: const Duration(seconds: 20));
      if (reply['type'] != 'MEDIA_STATUS') throw CastException('${reply['type']}${reply['reason'] != null ? ': ${reply['reason']}' : ''}');
      final status = parseMediaStatus(reply);
      if (status != null) {
        _mediaSessionId = status.sessionId;
        _duration = status.status.duration;
      }
    } catch (e) {
      await close();
      rethrow;
    }
  }

  Future<void> _control(String type, [Map<String, Object?> extra = const {}]) async {
    final transport = _transportId;
    final session = _mediaSessionId;
    if (transport == null || session == null) throw const CastException('nothing is playing');
    final reply = await _request(castMediaNamespace, transport, {'type': type, 'mediaSessionId': session, ...extra});
    if (reply['type'] == 'INVALID_REQUEST' || reply['type'] == 'INVALID_PLAYER_STATE') throw CastException('${reply['reason'] ?? reply['type']}');
  }

  @override
  Future<void> play() => _control('PLAY');
  @override
  Future<void> pause() => _control('PAUSE');
  @override
  Future<void> seek(Duration position) => _control('SEEK', {'currentTime': position.inMilliseconds / 1000});

  @override
  Future<void> stop() async {
    try {
      if (_sessionId case final session?) {
        await _request(castReceiverNamespace, 'receiver-0', {'type': 'STOP', 'sessionId': session}, timeout: const Duration(seconds: 3));
      }
    } on CastException catch (e) {
      logInfo('Chromecast stop failed: $e');
    } finally {
      await close();
    }
  }

  @override
  Future<CastStatus?> status() async {
    final transport = _transportId;
    if (transport == null) return null;
    try {
      final reply = await _request(castMediaNamespace, transport, {'type': 'GET_STATUS'}, timeout: const Duration(seconds: 4));
      final media = parseMediaStatus(reply);
      if (media == null) return const CastStatus(state: CastState.stopped);
      _mediaSessionId = media.sessionId;
      if (media.status.duration > Duration.zero) _duration = media.status.duration;
      return CastStatus(state: media.status.state, position: media.status.position, duration: _duration);
    } on CastException {
      return null;
    }
  }

  @override
  Future<void> close() async {
    _heartbeat?.cancel();
    final socket = _socket;
    _socket = null;
    _transportId = _sessionId = _mediaSessionId = null;
    for (final waiting in _pending.values) {
      if (!waiting.isCompleted) waiting.completeError(const CastException('connection lost'));
    }
    _pending.clear();
    socket?.destroy();
  }
}

/// Searches the LAN for Chromecasts for [timeout].
Stream<CastDevice> discoverChromecasts({Duration timeout = const Duration(seconds: 6)}) =>
    discoverMdns(timeout: timeout).map(ChromecastDevice.fromService);
