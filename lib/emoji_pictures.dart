import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Pictures of YouTube's own emoji (`:face-red-heart-shape:`), learned from
/// every comment and chat message that came with them, so a comment that
/// carries only the shortcut is still drawn. A channel's emoji
/// (`:_name:`) mean something else on each channel and are not kept.
abstract final class EmojiPictures {
  static final Map<String, String> _known = {};
  static File? _file;
  static Timer? _save;

  static final _shortcut = RegExp(r':[a-z0-9][a-z0-9-]*:');

  /// Reads what was learned before from [file], where it keeps learning.
  static Future<void> configure(File file) async {
    _file = file;
    try {
      final saved = jsonDecode(await file.readAsString());
      if (saved is Map) {
        for (final MapEntry(:key, :value) in saved.entries) {
          if (key is String && value is String) _known.putIfAbsent(key, () => value);
        }
      }
    } catch (_) {}
  }

  /// [emojis], what a comment or message came with, kept for later.
  static void learn(Map<String, String> emojis) {
    var added = false;
    for (final MapEntry(:key, :value) in emojis.entries) {
      if (_shortcut.matchAsPrefix(key)?.end == key.length && _known[key] != value) {
        _known[key] = value;
        added = true;
      }
    }
    if (added && _file != null) {
      _save?.cancel();
      _save = Timer(const Duration(seconds: 5), () {
        final file = _file;
        if (file != null) unawaited(file.writeAsString(jsonEncode(_known)).then((_) {}, onError: (_) {}));
      });
    }
  }

  /// [emojis] with the learned pictures of YouTube's emoji written in
  /// [text] that it lacks; [emojis] itself when there are none.
  static Map<String, String> fill(String text, Map<String, String> emojis) {
    learn(emojis);
    Map<String, String>? out;
    for (final match in _shortcut.allMatches(text)) {
      final name = match[0]!;
      final url = _known[name];
      if (url != null && !emojis.containsKey(name)) (out ??= {...emojis})[name] = url;
    }
    return out ?? emojis;
  }

  static void reset() => _known.clear();
}
