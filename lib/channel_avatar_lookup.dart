import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'channel_avatars.dart';
import 'models.dart';

/// The pictures of channels shown where no listing gave one (the watch
/// page, a channel's page and its posts), looked up once each by
/// [ChannelAvatars] and kept on disk, so a page shows the letter only until
/// the picture is known.
class ChannelAvatarLookup extends ChangeNotifier {
  ChannelAvatarLookup._();
  static final instance = ChannelAvatarLookup._();

  /// Pictures kept; the oldest go first.
  static const keep = 2000;
  /// Lookups at once.
  static const parallel = 2;

  ChannelAvatars? _source;
  File? _file;
  final _known = <String, String>{};
  final _tried = <String>{};
  final _waiting = <String>[];
  var _running = 0;
  Timer? _save;

  void configure(http.Client client, File file) {
    _source = ChannelAvatars(client);
    _file = file;
    try {
      final saved = jsonDecode(file.readAsStringSync());
      if (saved is Map) {
        for (final entry in saved.entries) {
          final url = ChannelRef.avatarUrl(entry.value);
          if (ChannelRef.isValidId(entry.key.toString()) && url != null) _known[entry.key.toString()] = url;
        }
      }
    } catch (_) {
      // Not saved yet, or unreadable: looked up again.
    }
  }

  /// The picture of channel [id], or null while it is looked up (once) or
  /// when it has none.
  String? of(String? id) {
    if (id == null || !ChannelRef.isValidId(id)) return null;
    final known = _known[id];
    if (known != null || _source == null || !_tried.add(id)) return known;
    _waiting.add(id);
    scheduleMicrotask(_pump);
    return null;
  }

  /// Keeps a picture a listing gave, so other pages of the channel show it.
  void remember(String id, String? url) {
    if (url == null || !ChannelRef.isValidId(id) || _known[id] == url) return;
    _put(id, url);
  }

  void _put(String id, String url) {
    _known.remove(id);
    _known[id] = url;
    while (_known.length > keep) {
      _known.remove(_known.keys.first);
    }
    _save?.cancel();
    _save = Timer(const Duration(seconds: 2), _write);
  }

  void _pump() {
    final source = _source;
    while (source != null && _running < parallel && _waiting.isNotEmpty) {
      final id = _waiting.removeLast();
      _running++;
      source.fetch(ChannelRef(id, '')).then((url) {
        if (url != null) {
          _put(id, url);
          notifyListeners();
        }
      }, onError: (Object _) {
        // Offline or refused: the letter stays this session.
      }).whenComplete(() {
        _running--;
        _pump();
      });
    }
  }

  Future<void> _write() async {
    final file = _file;
    if (file == null) return;
    try {
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(_known));
    } catch (_) {
      // Kept in memory; written again with the next picture.
    }
  }

  @visibleForTesting
  void reset() {
    _source = null;
    _file = null;
    _known.clear();
    _tried.clear();
    _waiting.clear();
    _running = 0;
    _save?.cancel();
  }
}
