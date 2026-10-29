import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'app_log.dart';
import 'models.dart';
import 'native_core.dart';
import 'youtube_player_probe.dart';

/// How far the AI filter goes.
enum AiFilterMode {
  off,

  /// Videos YouTube labels as made with AI.
  labeled,

  /// Those and the channels on KillSlop's and AiSList's lists of AI
  /// channels.
  labeledAndList;

  static AiFilterMode parse(Object? raw) => values.where((m) => m.name == raw).firstOrNull ?? off;
}

/// Hides AI-made videos from lists. YouTube's listings do not say which
/// videos it labels as made with AI; each video's `/next` answer does
/// (see `ai_label` in the Rust core), so videos are asked about once as
/// they show and the answers are kept on disk. The AI channel lists of
/// KillSlop (https://killslop.app, CC BY-SA 4.0) and AiSList
/// (https://github.com/Override92/AiSList, CC BY-NC 4.0, as channel ids
/// from https://github.com/theSiegs/aislist-channel-ids) are downloaded
/// once a day when asked for and never shipped with Lumtub. A list drops
/// a video once its answer is in, which [version] counts.
class AiFilter extends ChangeNotifier {
  AiFilter(this._client, {this.labelsFile, this.channelsFile});

  final http.Client _client;
  final File? labelsFile;
  final File? channelsFile;

  /// Where each AI channel list comes from, by the name it is kept under.
  static const lists = {
    'killslop': 'https://api.killslop.app/api/v1/export/youtube-channels.json',
    'aislist': 'https://raw.githubusercontent.com/theSiegs/aislist-channel-ids/main/lists/aislist_blocklist_ids.txt',
  };
  static const _fields = 'contents.twoColumnWatchNextResults.results.results.contents.videoPrimaryInfoRenderer.badges';
  static const parallel = 4;
  static const _kept = 20000;

  late final _probe = YoutubePlayerProbe(_client);

  AiFilterMode mode = AiFilterMode.off;
  Map<String, bool>? _labels;
  Set<String> _channels = const {};
  Map<String, List<String>> _listed = const {};
  DateTime? _listFetched;
  final _pending = <String>{};
  final _queue = <String>[];
  int _running = 0;
  Timer? _save;
  bool _loading = false;

  /// Goes up each time an answer hides a video.
  int version = 0;

  static bool get available => NativeCore.instance != null;

  /// Whether [item] is hidden: labeled as AI, or by a listed channel.
  bool hides(VideoItem item) {
    if (mode == AiFilterMode.off) return false;
    if (_labels?[item.id] == true) return true;
    final channel = item.channelId;
    return mode == AiFilterMode.labeledAndList && channel != null && (_channels.contains(channel) || _channels.contains(item.channel.toLowerCase()));
  }

  /// Sets [next] and loads what it needs.
  Future<void> setMode(AiFilterMode next) async {
    if (next == mode) return;
    mode = next;
    version++;
    notifyListeners();
    if (next == AiFilterMode.off) return;
    await _loadOnce();
    if (next == AiFilterMode.labeledAndList) await refreshList();
  }

  /// Asks about the videos of [items] not asked about yet.
  void check(Iterable<VideoItem> items) {
    if (mode == AiFilterMode.off || !available) return;
    final labels = _labels;
    if (labels == null) {
      unawaited(_loadOnce());
      return;
    }
    for (final item in items) {
      if (labels.containsKey(item.id) || !_pending.add(item.id)) continue;
      _queue.add(item.id);
    }
    _pump();
  }

  void _pump() {
    while (_running < parallel && _queue.isNotEmpty) {
      final id = _queue.removeLast();
      _running++;
      unawaited(_ask(id).whenComplete(() {
        _running--;
        _pending.remove(id);
        _pump();
      }));
    }
  }

  /// Whether a masked answer has told anything yet; when it never does,
  /// YouTube's answer shape moved and whole answers are asked for.
  static bool _maskWorks = true;

  Future<void> _ask(String id) async {
    try {
      var ai = await _read(await _probe.fetch(id, _maskWorks ? _fields : null, endpoint: 'next'));
      if (ai == null && _maskWorks) {
        ai = await _read(await _probe.fetch(id, null, endpoint: 'next'));
        if (ai != null) {
          _maskWorks = false;
          logInfo('The /next field mask left out the AI label; asking for whole answers');
        }
      }
      if (ai == null) return;
      final labels = _labels!;
      if (labels.length >= _kept) labels.remove(labels.keys.first);
      labels[id] = ai;
      _save ??= Timer(const Duration(seconds: 10), _write);
      if (ai && mode != AiFilterMode.off) {
        logInfo('YouTube labels $id as made with AI; hidden');
        version++;
        notifyListeners();
      }
    } catch (e) {
      logInfo('Could not ask whether $id is labeled as AI: $e');
    }
  }

  static Future<bool?> _read(List<int> bytes) => Isolate.run(() {
        final core = NativeCore.instance!;
        final read = jsonDecode(core.take(core.withBytes(bytes, core.aiLabel)) ?? '{}');
        return read is Map ? read['ai'] as bool? : null;
      });

  Future<void> _loadOnce() async {
    if (_labels != null || _loading) return;
    _loading = true;
    try {
      final labelsPath = labelsFile?.path;
      final channelsPath = channelsFile?.path;
      final (labels, listed, fetched) = await Isolate.run(() {
        var labels = <String, bool>{};
        var listed = <String, List<String>>{};
        DateTime? fetched;
        try {
          if (labelsPath != null && File(labelsPath).existsSync()) {
            labels = (jsonDecode(File(labelsPath).readAsStringSync()) as Map<String, dynamic>).map((k, v) => MapEntry(k, v == true));
          }
        } catch (_) {}
        try {
          if (channelsPath != null && File(channelsPath).existsSync()) {
            final file = File(channelsPath);
            final kept = jsonDecode(file.readAsStringSync());
            listed = kept is Map
                ? {for (final e in kept.entries) e.key.toString(): [for (final c in e.value as List) c.toString()]}
                : {'killslop': [for (final c in kept as List) c.toString()]};
            fetched = kept is Map ? file.lastModifiedSync() : null;
          }
        } catch (_) {}
        return (labels, listed, fetched);
      });
      _labels = labels;
      _setListed(listed);
      _listFetched = fetched;
      version++;
      notifyListeners();
    } finally {
      _loading = false;
    }
  }

  void _setListed(Map<String, List<String>> listed) {
    _listed = listed;
    _channels = {for (final list in listed.values) ...list};
  }

  /// Downloads the AI channel lists when the copies kept are a day old. A
  /// list that cannot be downloaded keeps its last copy.
  Future<void> refreshList({bool force = false}) async {
    if (mode != AiFilterMode.labeledAndList || !available) return;
    final fetched = _listFetched;
    if (!force && fetched != null && DateTime.now().difference(fetched) < const Duration(days: 1)) return;
    final listed = Map<String, List<String>>.of(_listed);
    var changed = false;
    for (final MapEntry(key: name, value: url) in lists.entries) {
      try {
        final response = await _client.get(Uri.parse(url)).timeout(const Duration(seconds: 30));
        if (response.statusCode != 200) throw StateError('HTTP ${response.statusCode}');
        final body = response.bodyBytes;
        final channels = await Isolate.run(() {
          final core = NativeCore.instance!;
          return [for (final c in jsonDecode(core.take(core.withBytes(body, core.aiChannels)) ?? '[]') as List) c.toString()];
        });
        if (channels.isEmpty) throw StateError('the list is empty');
        listed[name] = channels;
        changed = true;
        logInfo('AI channel list $name: ${channels.length} channels');
      } catch (e) {
        logInfo('Could not download the AI channel list $name: $e');
      }
    }
    if (!changed) return;
    _setListed(listed);
    _listFetched = DateTime.now();
    final path = channelsFile?.path;
    if (path != null) {
      await Isolate.run(() {
        final file = File(path);
        file.parent.createSync(recursive: true);
        file.writeAsStringSync(jsonEncode(listed));
      }).catchError((Object e) => logInfo('Could not save the AI channel lists: $e'));
    }
    version++;
    notifyListeners();
  }

  /// Channels on the downloaded list.
  int get listedChannels => _channels.length;

  void _write() {
    _save = null;
    final labels = _labels;
    final path = labelsFile?.path;
    if (labels == null || path == null) return;
    final copy = Map<String, bool>.of(labels);
    unawaited(Isolate.run(() {
      final file = File(path);
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(jsonEncode(copy));
    }).catchError((Object e) => logInfo('Could not save AI labels: $e')));
  }
}
