import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'app_log.dart';
import 'l10n/l10n.dart';

/// [error] as one sentence a person can act on, such as “连不上 YouTube，
/// 请检查网络或代理”, for the common network failures; anything else is its
/// own message without the exception's type name. The full error is logged.
String friendlyError(Object error) {
  final raw = '$error';
  logWarn('Shown as an error: $raw');
  final text = raw.toLowerCase();
  if (error is TimeoutException || text.contains('timed out') || text.contains('timeout')) return tr('The network timed out; check the network or proxy');
  if (RegExp(r'\b429\b').hasMatch(text) || text.contains('too many requests')) return tr('Too many requests; YouTube is limiting access for now, try again later');
  if (text.contains('certificate') || text.contains('handshake') || error is HandshakeException || error is TlsException) return tr('The secure connection failed; the proxy or a certificate may be the cause');
  if (error is SocketException ||
      text.contains('could not connect') ||
      text.contains('connection refused') ||
      text.contains('connection reset') ||
      text.contains('failed host lookup') ||
      text.contains('network is unreachable') ||
      text.contains('dns error')) {
    return tr("Can't reach YouTube; check the network or proxy");
  }
  if (RegExp(r'\b403\b').hasMatch(text)) return tr('YouTube refused the request (403); try again later or use another proxy');
  var message = error is http.ClientException ? error.message : raw;
  message = message.replaceFirst(RegExp(r'^(\w+(Exception|Error)):\s*'), '').trim();
  return message.isEmpty ? tr('Something went wrong; please try again') : message;
}
