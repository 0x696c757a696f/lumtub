import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../app_directories.dart';
import '../app_log.dart';
import 'video_words.dart';

/// How much of each video the learner knew when its subtitles were last
/// read, kept so its card can say how hard it is before it is opened
/// again; and which videos the words being learnt were heard in. Only videos whose subtitles Lumtub already had are here: none
/// are fetched for it, so lists never send YouTube extra requests.
class VideoDifficulty extends ChangeNotifier {
  /// Enough for a long history; the oldest go first.
  static const limit = 3000;

  /// Words kept with the videos they were heard in; the oldest go first.
  static const wordLimit = 5000;

  /// Videos kept for each word: enough to say how often it comes up.
  static const videosPerWord = 30;

  File? _file;
  final _known = <String, double>{};
  final _seen = <String, List<String>>{};
  Timer? _saving;

  /// Reads what was kept in [file]; later [remember]s are saved there.
  Future<void> open(File file) async {
    if (_file?.path == file.path) return;
    _file = file;
    try {
      if (!await file.exists()) return;
      final json = jsonDecode(await file.readAsString());
      final videos = json is Map ? json['videos'] : null;
      if (videos is! Map) return;
      for (final MapEntry(:key, :value) in videos.entries) {
        if (value is num && value.isFinite && value >= 0 && value <= 1 && _id.hasMatch('$key')) _known['$key'] = value.toDouble();
      }
      final seen = json['seen'];
      if (seen is Map) {
        for (final MapEntry(:key, :value) in seen.entries) {
          if (value is List) _seen['$key'] = [for (final id in value.whereType<String>().take(videosPerWord)) if (_id.hasMatch(id)) id];
        }
      }
      notifyListeners();
    } catch (e) {
      logWarn('Could not read the video difficulties: $e');
    }
  }

  static final _id = RegExp(r'^[A-Za-z0-9_-]{11}$');

  /// The share of [id]'s words known, from 0 to 1, when it was last read.
  double? knownOf(String id) => _known[id];

  VideoLevel? levelOf(String id) => switch (_known[id]) {
        final known? => VideoWords.levelFor(known),
        null => null,
      };

  /// How many videos the word with [key] (`language:word`) was heard in.
  int videosWith(String key) => _seen[key]?.length ?? 0;

  /// Notes that the words with [keys] were heard in the video [id]: only
  /// recorded, it does not change when a word comes up for review.
  void saw(String id, Iterable<String> keys) {
    if (!_id.hasMatch(id)) return;
    var changed = false;
    for (final key in keys) {
      final videos = _seen.remove(key) ?? <String>[];
      if (!videos.contains(id)) {
        videos.add(id);
        if (videos.length > videosPerWord) videos.removeAt(0);
        changed = true;
      }
      _seen[key] = videos;
    }
    while (_seen.length > wordLimit) {
      _seen.remove(_seen.keys.first);
    }
    if (changed) _changed();
  }

  /// Keeps [known] for [id], replacing an older reading.
  void remember(String id, double known) {
    if (!_id.hasMatch(id) || !known.isFinite) return;
    final value = double.parse(known.clamp(0.0, 1.0).toStringAsFixed(3));
    if (_known[id] == value) return;
    // Read again: it moves to the newest end.
    _known.remove(id);
    _known[id] = value;
    while (_known.length > limit) {
      _known.remove(_known.keys.first);
    }
    _changed();
  }

  void _changed() {
    notifyListeners();
    _saving?.cancel();
    _saving = Timer(const Duration(seconds: 2), () => unawaited(_save()));
  }

  Future<void> _save() async {
    final file = _file;
    if (file == null) return;
    try {
      await writeFileAtomic(file, jsonEncode({'version': 1, 'videos': _known, 'seen': _seen}));
    } catch (e) {
      logError('Could not save the video difficulties', e);
    }
  }
}

/// The learner's video difficulties, for the cards of every list.
final videoDifficulty = VideoDifficulty();
