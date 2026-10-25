import 'dart:convert';
import 'dart:isolate';

/// Below this size decoding takes less time than starting an isolate.
const _inlineLimit = 64 * 1024;

/// [text] decoded away from the UI isolate, so a video's metadata (often
/// a megabyte or more) does not stall a frame.
Future<Object?> decodeJsonInBackground(String text) async {
  if (text.length < _inlineLimit) return jsonDecode(text);
  return Isolate.run(() => jsonDecode(text));
}

/// [bytes] as UTF-8 JSON, decoded away from the UI isolate.
Future<Object?> decodeUtf8JsonInBackground(List<int> bytes) async {
  if (bytes.length < _inlineLimit) return jsonDecode(utf8.decode(bytes));
  return Isolate.run(() => jsonDecode(utf8.decode(bytes)));
}
