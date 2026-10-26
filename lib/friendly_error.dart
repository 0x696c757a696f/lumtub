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
  logInfo('Shown as an error: $raw');
  final text = raw.toLowerCase();
  if (error is TimeoutException || text.contains('timed out') || text.contains('timeout')) return tr('网络超时，请检查网络或代理');
  if (RegExp(r'\b429\b').hasMatch(text) || text.contains('too many requests')) return tr('请求太频繁，YouTube 暂时限制了访问，请稍后再试');
  if (text.contains('certificate') || text.contains('handshake') || error is HandshakeException || error is TlsException) return tr('安全连接失败，可能是代理或证书的问题');
  if (error is SocketException ||
      text.contains('could not connect') ||
      text.contains('connection refused') ||
      text.contains('connection reset') ||
      text.contains('failed host lookup') ||
      text.contains('network is unreachable') ||
      text.contains('dns error')) {
    return tr('连不上 YouTube，请检查网络或代理');
  }
  if (RegExp(r'\b403\b').hasMatch(text)) return tr('YouTube 拒绝了这次请求（403），请稍后再试或换个代理');
  var message = error is http.ClientException ? error.message : raw;
  message = message.replaceFirst(RegExp(r'^(\w+(Exception|Error)):\s*'), '').trim();
  return message.isEmpty ? tr('出了点问题，请重试') : message;
}
