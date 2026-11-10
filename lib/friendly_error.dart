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
  if (error is TimeoutException || RegExp(r'(operation|connection|request|read|connect) timed out|timed out (connecting|waiting)|deadline has elapsed').hasMatch(text)) {
    return tr('The network timed out; check the network or proxy');
  }
  if (RegExp(r'\b(http|status|code|error)\W{0,3}429\b|\b429 too many').hasMatch(text) || text.contains('too many requests')) {
    return tr('Too many requests; YouTube is limiting access for now, try again later');
  }
  if (error is HandshakeException || error is TlsException || text.contains('certificate_verify_failed') || text.contains('certificate verify failed') || text.contains('handshake failed') || text.contains('unknown ca')) {
    return tr('The secure connection failed; the proxy or a certificate may be the cause');
  }
  if (error is SocketException ||
      text.contains('could not connect') ||
      text.contains('connection refused') ||
      text.contains('connection reset') ||
      text.contains('failed host lookup') ||
      text.contains('network is unreachable') ||
      text.contains('dns error')) {
    return tr("Can't reach YouTube; check the network or proxy");
  }
  if (RegExp(r'\b(http|status|code|error)\W{0,3}403\b|\b403 forbidden').hasMatch(text)) return tr('YouTube refused the request (403); try again later or use another proxy');
  var message = error is http.ClientException ? error.message : raw;
  message = message.replaceFirst(RegExp(r'^(\w+(Exception|Error)):\s*'), '').trim();
  return message.isEmpty ? tr('Something went wrong; please try again') : message;
}

/// A file or folder failure as a sentence about the disk, such as
/// “磁盘已满”; other errors go through [friendlyError]. The full error is
/// logged.
String friendlyFileError(Object error) {
  if (error is! FileSystemException) return friendlyError(error);
  logWarn('Shown as an error: $error');
  final code = error.osError?.errorCode;
  final text = '${error.osError?.message ?? ''} ${error.message}'.toLowerCase();
  // Error numbers mean different things on Windows and elsewhere.
  final full = Platform.isWindows ? const {39, 112} : const {28};
  final denied = Platform.isWindows ? const {5} : const {1, 13, 30};
  if (text.contains('no space left') || text.contains('not enough space') || full.contains(code)) return tr('The disk is full; free some space and try again');
  if (text.contains('permission denied') || text.contains('access is denied') || text.contains('operation not permitted') || text.contains('read-only') || denied.contains(code)) {
    return tr('No permission to use that folder; choose another one');
  }
  if (text.contains('no such file') || text.contains('cannot find the') || text.contains('not found') || code == 2 || (Platform.isWindows && code == 3)) return tr("The file or folder wasn't found");
  return tr("Couldn't use the file or folder; check that it is available and try again");
}

/// What yt-dlp printed when a download failed, as one sentence a person can
/// act on; anything it doesn't recognise becomes a general failure, with the
/// original text only in the log.
String friendlyDownloadError(String raw) {
  logWarn('Download failed: $raw');
  final text = raw.toLowerCase();
  bool has(String phrase) => text.contains(phrase);
  if (has('no space left') || has('not enough space')) return tr('The disk is full; free some space and try again');
  if (has('permission denied') || has('access is denied')) return tr('No permission to use that folder; choose another one');
  if (has('confirm your age') || has('age-restricted') || has('inappropriate for some users')) return tr('This video is age-restricted and cannot be downloaded');
  if (has('confirm you') && has('not a bot') || has('sign in to confirm')) return tr("YouTube wants to confirm you're not a bot; sign in or try another network");
  if (has('private video')) return tr('This video is private');
  if (has('members-only') || has('join this channel')) return tr('This video is for channel members only');
  if (has('ffmpeg') && (has('not found') || has('not installed') || has('is not available'))) return tr('ffmpeg is needed for this download but was not found');
  if (has('requested format is not available') || has('no video formats found')) return tr("The chosen format isn't available for this video; pick another");
  if (has('not available in your country') || has('available in your country') || has('blocked it in your country') || has('geo restricted') || has('geo-restricted')) return tr("This video isn't available in your region");
  if (has('video unavailable') || has('is not available') || has('has been removed') || has('video is unavailable')) return tr("This video isn't available");
  if (RegExp(r'\b(http error|status|code)\W{0,3}429\b').hasMatch(text) || has('too many requests')) return tr('Too many requests; YouTube is limiting access for now, try again later');
  if (RegExp(r'\b(http error|status|code)\W{0,3}403\b').hasMatch(text)) return tr('YouTube refused the request (403); try again later or use another proxy');
  if (has('timed out') || has('getaddrinfo failed') || has('name or service not known') || has('temporary failure in name resolution') || has('network is unreachable') || has('connection refused') || has('connection reset') || has('unable to download')) {
    return tr("Can't reach YouTube; check the network or proxy");
  }
  return tr('The download failed; see the logs for details');
}
