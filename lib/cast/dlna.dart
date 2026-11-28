import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../app_log.dart';
import '../network_proxy.dart' show isLocalHost;
import 'cast_device.dart';
import 'cast_net.dart';
import 'cast_parse.dart';

// DLNA / UPnP AV casting: SSDP search for MediaRenderers, then SOAP calls to
// their AVTransport service. What devices send is read in the Rust core
// (cast_lan.rs); sockets are dart:io.

const mediaRendererType = 'urn:schemas-upnp-org:device:MediaRenderer:1';
const avTransportPrefix = 'urn:schemas-upnp-org:service:AVTransport:';

/// The SSDP search for UPnP media renderers.
String ssdpSearchRequest({int mx = 2}) => 'M-SEARCH * HTTP/1.1\r\n'
    'HOST: 239.255.255.250:1900\r\n'
    'MAN: "ssdp:discover"\r\n'
    'MX: $mx\r\n'
    'ST: $mediaRendererType\r\n'
    'USER-AGENT: Lumtub UPnP/1.1\r\n\r\n';

/// The fields of an SSDP reply that matter here.
class SsdpResponse {
  const SsdpResponse({required this.location, this.usn = '', this.st = ''});
  final Uri location;
  final String usn;
  final String st;
}

/// An SSDP search reply (or NOTIFY), or null when it names no http location.
SsdpResponse? parseSsdpResponse(String text) {
  final Object? read;
  try {
    read = readTextInCore('lumtub_ssdp', text);
  } on FormatException {
    return null;
  }
  if (read is! Map) return null;
  final headers = read;
  String header(String name) => headers[name] is String ? headers[name] as String : '';
  final location = Uri.tryParse(header('location'));
  if (location == null || !location.hasScheme || !location.scheme.startsWith('http') || location.host.isEmpty) return null;
  return SsdpResponse(location: location, usn: header('usn'), st: headers['st'] is String ? header('st') : header('nt'));
}

/// Whether [host] (from an address) is [address].
bool sameAddress(String host, InternetAddress address) {
  final ip = InternetAddress.tryParse(host.startsWith('[') ? host.substring(1, host.length - 1) : host);
  return ip != null && ip.address == address.address;
}

String xmlEscape(String text) => text.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;').replaceAll("'", '&apos;');

String xmlUnescape(String text) => text
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAllMapped(RegExp(r'&#(x?)([0-9a-fA-F]+);'), (m) {
      final code = int.tryParse(m[2]!, radix: m[1]!.isEmpty ? 10 : 16);
      final valid = code != null && code > 0 && code <= 0x10FFFF && !(code >= 0xD800 && code <= 0xDFFF);
      return valid ? String.fromCharCode(code) : m[0]!;
    })
    .replaceAll('&amp;', '&');

/// One service of a UPnP device.
class UpnpService {
  const UpnpService(this.type, this.controlUrl);
  final String type;
  final Uri controlUrl;
}

/// A UPnP device description, as far as casting needs it.
class DlnaDescription {
  const DlnaDescription({required this.name, required this.udn, required this.services, this.apple = false});
  final String name;
  final String udn;
  final List<UpnpService> services;
  /// Whether the renderer runs on an iPhone, iPad or Mac, where players
  /// take a transport stream only as HLS.
  final bool apple;

  UpnpService? get avTransport => services.where((s) => s.type.startsWith(avTransportPrefix)).firstOrNull;
}

/// Whether [a] and [b] name the same host and port.
bool _sameHost(Uri a, Uri b) => a.host.toLowerCase() == b.host.toLowerCase() && a.port == b.port;

/// Reads the description at [location]; control addresses are made absolute
/// against `URLBase` or [location]. A `URLBase` or control address on
/// another host than [location] is ignored, so a device cannot point Lumtub
/// at some other machine.
DlnaDescription parseDeviceDescription(String xml, Uri location) {
  final read = readTextInCore('lumtub_upnp_description', xml);
  final found = read is Map<String, Object?> ? read : const <String, Object?>{};
  String? text(String name) {
    final value = found[name];
    return value is String ? value : null;
  }

  final baseText = text('URLBase');
  final named = baseText == null ? null : Uri.tryParse(baseText);
  final base = named != null && named.hasScheme && named.scheme.startsWith('http') && _sameHost(named, location) ? named : location;
  final services = <UpnpService>[];
  final listed = found['services'];
  for (final service in listed is List ? listed : const []) {
    if (service is! Map || service['type'] is! String || service['control'] is! String) continue;
    final address = controlAddress(base, service['control'] as String);
    if (!address.scheme.startsWith('http') || !_sameHost(address, location)) continue;
    services.add(UpnpService(service['type'] as String, address));
  }
  final name = text('friendlyName');
  final about = [name, for (final tag in ['manufacturer', 'modelName', 'modelDescription']) text(tag)].whereType<String>().join(' ');
  return DlnaDescription(name: name == null || name.isEmpty ? location.host : name, udn: text('UDN') ?? location.toString(), services: services, apple: looksApple(about));
}

/// Where a service's [control] path points from [base]. Lebo (乐播)
/// receivers write a bare `_urn:…` path, which reads as a bad scheme; it is a
/// path next to the description.
Uri controlAddress(Uri base, String control) {
  try {
    return base.resolve(control);
  } on FormatException {
    return base.resolve('./$control');
  }
}

/// Whether a renderer described as [about] runs on Apple's systems.
bool looksApple(String about) => RegExp(r'\b(iPhone|iPad|iPod|iOS|iPadOS|tvOS|Apple TV|macOS|Mac|MacBook|iMac|Apple)\b', caseSensitive: false).hasMatch(about);

/// The SOAP request body for [action] of [serviceType].
String soapEnvelope(String serviceType, String action, Map<String, String> arguments) => '<?xml version="1.0" encoding="utf-8"?><s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"><s:Body><u:$action xmlns:u="$serviceType">${arguments.entries.map((e) => '<${e.key}>${xmlEscape(e.value)}</${e.key}>').join()}</u:$action></s:Body></s:Envelope>';

/// The output arguments of a SOAP response, or throws [CastException] with
/// the UPnP error when the body is a fault.
Map<String, String> parseSoapResponse(String xml) {
  final read = readTextInCore('lumtub_soap_response', xml);
  final answer = read is Map<String, Object?> ? read : const <String, Object?>{};
  if (answer['fault'] case final Map<String, Object?> fault) {
    final faultCode = fault['code'], faultDescription = fault['description'];
    final code = faultCode is String ? faultCode : null;
    final description = faultDescription is String ? faultDescription : '';
    throw CastException('UPnP ${code ?? 'error'}${description.isEmpty ? '' : ': $description'}');
  }
  final args = answer['args'];
  return {if (args is Map) for (final MapEntry(:key, :value) in args.entries) '$key': '$value'};
}

/// DIDL-Lite metadata naming the video, which many renderers want. A
/// stream that is not [seekable] tells the renderer not to ask for byte
/// ranges.
///
/// [subtitles] is an SRT address, named the ways renderers look for one:
/// a second `res` (most), Samsung's `sec:CaptionInfoEx` and the
/// `upnp:subtitle` some players read. A renderer that knows none of them
/// plays without.
String didlLite({required String title, required String url, required String mime, bool seekable = true, String? subtitles}) =>
    '<DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/" xmlns:dlna="urn:schemas-dlna-org:metadata-1-0/"${subtitles == null ? '' : ' xmlns:sec="http://www.sec.co.kr/"'}><item id="0" parentID="-1" restricted="1"><dc:title>${xmlEscape(title)}</dc:title><upnp:class>object.item.videoItem</upnp:class><res protocolInfo="http-get:*:$mime:DLNA.ORG_OP=${seekable ? '01' : '00'};DLNA.ORG_FLAGS=01700000000000000000000000000000">${xmlEscape(url)}</res>${subtitles == null ? '' : '<res protocolInfo="http-get:*:text/srt:*">${xmlEscape(subtitles)}</res><sec:CaptionInfoEx sec:type="srt">${xmlEscape(subtitles)}</sec:CaptionInfoEx><sec:CaptionInfo sec:type="srt">${xmlEscape(subtitles)}</sec:CaptionInfo><upnp:subtitle>${xmlEscape(subtitles)}</upnp:subtitle>'}</item></DIDL-Lite>';

/// `H:MM:SS` as UPnP writes positions.
String formatUpnpTime(Duration time) {
  final s = time.inSeconds;
  return '${s ~/ 3600}:${(s ~/ 60 % 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
}

/// A UPnP time such as `0:01:23` or `00:01:23.500`; null for `NOT_IMPLEMENTED`
/// and the like.
Duration? parseUpnpTime(String? text) {
  final m = RegExp(r'^\+?(\d+):(\d{1,2}):(\d{1,2})(?:\.(\d+))?').firstMatch(text?.trim() ?? '');
  if (m == null) return null;
  return Duration(hours: int.parse(m[1]!), minutes: int.parse(m[2]!), seconds: int.parse(m[3]!), milliseconds: m[4] == null ? 0 : (double.parse('0.${m[4]}') * 1000).round());
}

CastState dlnaState(String? transportState) => switch (transportState) {
      'PLAYING' => CastState.playing,
      'PAUSED_PLAYBACK' || 'PAUSED_RECORDING' => CastState.paused,
      'TRANSITIONING' => CastState.loading,
      _ => CastState.stopped,
    };

/// A UPnP media renderer, driven through its AVTransport service.
class DlnaDevice implements CastDevice {
  DlnaDevice({required this.name, required this.id, required this.serviceType, required this.controlUrl, this.apple = false, HttpClient? client})
      : _client = (client ?? HttpClient())..connectionTimeout = const Duration(seconds: 5);

  @override
  final String name;
  @override
  final String id;
  @override
  CastProtocol get protocol => CastProtocol.dlna;
  @override
  String get host => controlUrl.host;
  @override
  int get port => controlUrl.port;
  final String serviceType;
  final Uri controlUrl;
  /// See [DlnaDescription.apple].
  final bool apple;
  final HttpClient _client;

  Future<Map<String, String>> _soap(String action, [Map<String, String> arguments = const {}]) async {
    final body = utf8.encode(soapEnvelope(serviceType, action, {'InstanceID': '0', ...arguments}));
    try {
      final request = await _client.postUrl(controlUrl);
      request.headers
        ..set('Content-Type', 'text/xml; charset="utf-8"')
        ..set('SOAPACTION', '"$serviceType#$action"', preserveHeaderCase: true);
      request.followRedirects = false;
      request.contentLength = body.length;
      request.add(body);
      final response = await request.close().timeout(const Duration(seconds: 8));
      final text = await readDeviceReply(response).timeout(const Duration(seconds: 8));
      if (response.statusCode >= 400 && !text.contains('Fault>')) throw CastException('HTTP ${response.statusCode}');
      return parseSoapResponse(text);
    } on SocketException catch (e) {
      throw CastException(e.message);
    } on TimeoutException {
      throw const CastException('timed out');
    } on HttpException catch (e) {
      throw CastException(e.message);
    }
  }

  @override
  Future<void> load(CastMedia media) async {
    await _soap('SetAVTransportURI', {
      'CurrentURI': media.url,
      'CurrentURIMetaData': didlLite(title: media.title, url: media.url, mime: media.mime, seekable: media.restart == null, subtitles: media.subtitles?.srt),
    });
    await _soap('Play', {'Speed': '1'});
    if (media.start > const Duration(seconds: 1)) unawaited(_seekWhenReady(media.start));
  }

  /// Renderers refuse to seek before they play; tries until they do.
  Future<void> _seekWhenReady(Duration position) async {
    for (var i = 0; i < 12; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 700));
      try {
        final s = await status();
        if (s?.state == CastState.playing || s?.state == CastState.paused) {
          await seek(position);
          return;
        }
      } on CastException catch (e) {
        logWarn('DLNA seek failed: $e');
      }
    }
  }

  @override
  Future<void> play() => _soap('Play', {'Speed': '1'});
  @override
  Future<void> pause() => _soap('Pause');
  @override
  Future<void> seek(Duration position) => _soap('Seek', {'Unit': 'REL_TIME', 'Target': formatUpnpTime(position)});

  @override
  Future<void> stop() async {
    try {
      await _soap('Stop');
    } finally {
      await close();
    }
  }

  @override
  Future<CastStatus?> status() async {
    try {
      final transport = await _soap('GetTransportInfo');
      final position = await _soap('GetPositionInfo');
      return CastStatus(
        state: dlnaState(transport['CurrentTransportState']),
        position: parseUpnpTime(position['RelTime']) ?? Duration.zero,
        duration: parseUpnpTime(position['TrackDuration']) ?? Duration.zero,
      );
    } on CastException {
      return null;
    }
  }

  @override
  Future<void> close() async => _client.close(force: true);
}

/// Searches the LAN for media renderers for [timeout], emitting each once.
Stream<CastDevice> discoverDlna({Duration timeout = const Duration(seconds: 6)}) {
  final controller = StreamController<CastDevice>();
  final sockets = <RawDatagramSocket>[];
  final seen = <String>{};
  final http = HttpClient()..connectionTimeout = const Duration(seconds: 4);
  Timer? finish;
  Timer? repeat;
  var closed = false;

  Future<void> describe(SsdpResponse found) async {
    try {
      final request = await http.getUrl(found.location);
      // A device describes itself; it does not send Lumtub elsewhere.
      request.followRedirects = false;
      final response = await request.close().timeout(const Duration(seconds: 4));
      if (response.statusCode != 200) return;
      final xml = await readDeviceReply(response).timeout(const Duration(seconds: 4));
      final description = parseDeviceDescription(xml, found.location);
      final service = description.avTransport;
      if (service == null || !seen.add(description.udn) || controller.isClosed) return;
      controller.add(DlnaDevice(name: description.name, id: description.udn, serviceType: service.type, controlUrl: service.controlUrl, apple: description.apple));
    } catch (e) {
      logWarn('Could not read the DLNA device description ${found.location}: $e');
    }
  }

  Future<void> close() async {
    closed = true;
    finish?.cancel();
    repeat?.cancel();
    for (final s in sockets) {
      s.close();
    }
    http.close(force: true);
    if (!controller.isClosed) await controller.close();
  }

  controller.onListen = () async {
    final target = InternetAddress('239.255.255.250');
    final data = utf8.encode(ssdpSearchRequest());
    final locations = <String>{};
    for (final address in await localIPv4Addresses()) {
      if (closed) return;
      try {
        final socket = await RawDatagramSocket.bind(address, 0);
        // Cancelled while binding: close() has run already.
        if (closed) {
          socket.close();
          return;
        }
        sockets.add(socket);
        socket.listen((event) {
          if (event != RawSocketEvent.read) return;
          final packet = socket.receive();
          final found = packet == null ? null : parseSsdpResponse(utf8.decode(packet.data, allowMalformed: true));
          // Only a device on this network is asked for its description, and
          // only at its own address: a reply naming another host (this
          // computer, the router) would have Lumtub fetch that for it.
          if (found != null && isLocalHost(found.location.host) && sameAddress(found.location.host, packet!.address) && locations.add(found.location.toString())) {
            unawaited(describe(found));
          }
        });
      } on SocketException catch (e) {
        logWarn('DLNA discovery cannot use $address: ${e.message}');
      }
    }
    void search() {
      for (final s in sockets) {
        try {
          s.send(data, target, 1900);
        } on SocketException {
          // That interface is not usable now.
        }
      }
    }

    if (closed) return;
    search();
    repeat = Timer.periodic(const Duration(seconds: 2), (_) => search());
    finish = Timer(timeout, close);
  };
  controller.onCancel = close;
  return controller.stream;
}
