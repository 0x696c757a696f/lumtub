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

  /// Those and the channels on KillSlop's list of AI channels.
  labeledAndList;

  static AiFilterMode parse(Object? raw) => values.where((m) => m.name == raw).firstOrNull ?? off;
}

/// Hides AI-made videos from lists. YouTube's listings do not say which
/// videos it labels as made with AI; each video's `/next` answer does
/// (see `ai_label` in the Rust core), so videos are asked about once as
/// they show and the answers are kept on disk. KillSlop's channel list
/// (https://killslop.app, CC BY-SA 4.0) is downloaded once a day when
/// asked for. A list drops a video once its answer is in, which
/// [version] counts.
class AiFilter extends ChangeNotifier {
  AiFilter(this._client, {this.labelsFile, this.channelsFile});

  final http.Client _client;
  final File? labelsFile;
  final File? channelsFile;

  static const listUrl = 'https://api.killslop.app/api/v1/export/youtube-channels.json';
  static const _fields = 'contents.twoColumnWatchNextResults.results.results.contents.videoPrimaryInfoRenderer.badges';
  static const parallel = 4;
  static const _kept = 20000;

  late final _probe = YoutubePlayerProbe(_client);

  AiFilterMode mode = AiFilterMode.off;
  Map<String, bool>? _labels;
  Set<String> _channels = const {};
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
      final (labels, channels, fetched) = await Isolate.run(() {
        var labels = <String, bool>{};
        var channels = <String>{};
        DateTime? fetched;
        try {
          if (labelsPath != null && File(labelsPath).existsSync()) {
            labels = (jsonDecode(File(labelsPath).readAsStringSync()) as Map<String, dynamic>).map((k, v) => MapEntry(k, v == true));
          }
        } catch (_) {}
        try {
          if (channelsPath != null && File(channelsPath).existsSync()) {
            final file = File(channelsPath);
            channels = {for (final c in jsonDecode(file.readAsStringSync()) as List) c.toString()};
            fetched = file.lastModifiedSync();
          }
        } catch (_) {}
        return (labels, channels, fetched);
      });
      _labels = labels;
      _channels = channels;
      _listFetched = fetched;
      version++;
      notifyListeners();
    } finally {
      _loading = false;
    }
  }

  /// Downloads KillSlop's channel list when the copy kept is a day old.
  Future<void> refreshList({bool force = false}) async {
    if (mode != AiFilterMode.labeledAndList || !available) return;
    final fetched = _listFetched;
    if (!force && fetched != null && DateTime.now().difference(fetched) < const Duration(days: 1)) return;
    try {
      final response = await _client.get(Uri.parse(listUrl)).timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) throw StateError('HTTP ${response.statusCode}');
      final body = response.bodyBytes;
      final channels = await Isolate.run(() {
        final core = NativeCore.instance!;
        return [for (final c in jsonDecode(core.take(core.withBytes(body, core.aiChannels)) ?? '[]') as List) c.toString()];
      });
      if (channels.isEmpty) throw StateError('the list is empty');
      _channels = channels.toSet();
      _listFetched = DateTime.now();
      logInfo('AI channel list: ${channels.length} channels');
      final path = channelsFile?.path;
      if (path != null) {
        await Isolate.run(() {
          final file = File(path);
          file.parent.createSync(recursive: true);
          file.writeAsStringSync(jsonEncode(channels));
        });
      }
      version++;
      notifyListeners();
    } catch (e) {
      logInfo('Could not download the AI channel list: $e');
    }
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
