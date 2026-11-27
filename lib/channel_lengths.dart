import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/foundation.dart';

import 'channel_sort.dart';
import 'models.dart';
import 'native_core.dart';
import 'video_repository.dart';

/// A channel tab in an order YouTube does not offer (最长, 最短): read
/// newest first, then ordered by the core (native/lumtub_core/src/
/// channel_lengths.rs), which keeps what was read in [folder]. A tab read
/// in the last [fresh] is read only as far as the first videos it already
/// knows, so the second time costs one page instead of the whole tab.
class ChannelLengths {
  ChannelLengths({required this.newest, required this.channel, required this.tab, required this.sort, this.folder, Future<Object?> Function(Map<String, Object?> ask)? core, DateTime Function()? clock})
      : assert(sort.rank != null),
        _core = core ?? _native,
        _clock = clock ?? DateTime.now;

  final Listing Function() newest;
  final ChannelRef channel;
  final ChannelTab tab;
  final ChannelSort sort;
  /// Where the tabs read are kept; null keeps nothing.
  final String? folder;
  final Future<Object?> Function(Map<String, Object?> ask) _core;
  final DateTime Function() _clock;

  /// Entries read from YouTube so far, for the page to show.
  final read = ValueNotifier<int>(0);

  /// How old a saved tab may be before it is read again whole; until then
  /// only new uploads are read.
  static const fresh = Duration(days: 7);
  /// After this many known videos in a row the rest is known too. More
  /// than one, as a premiere or a video made public late can sit among
  /// older ones.
  static const knownRun = 3;
  static const _page = 100;

  /// The ask runs in its own isolate: the JSON, the merge, the order and
  /// the file work stay off the UI thread.
  static Future<Object?> _native(Map<String, Object?> ask) => Isolate.run(() {
        final answer = NativeCore.instance?.channelLengths(jsonEncode(ask));
        return answer == null ? null : jsonDecode(answer);
      });

  /// The tab's videos in [sort] order, as listing lines.
  Listing listing() => Listing(_lines, channel: channel);

  String get _tabName => tab == ChannelTab.live ? 'live' : 'videos';
  String get _order => sort == ChannelSort.shortest ? 'shortest' : 'longest';

  Stream<String> _lines() async* {
    final dir = folder;
    var known = const <String>{};
    if (dir != null) {
      final answer = await _ask({'op': 'known', 'dir': dir, 'channel': channel.id, 'tab': _tabName});
      final saved = answer is Map ? answer['saved'] : null;
      final ids = answer is Map ? answer['ids'] : null;
      final age = saved is int ? _clock().difference(DateTime.fromMillisecondsSinceEpoch(saved * 1000)) : null;
      if (age != null && age < fresh && !age.isNegative && ids is List) known = {for (final id in ids) if (id is String) id};
    }
    final found = <Map<String, dynamic>>[];
    final source = newest();
    var run = 0;
    var whole = false;
    Object? failure;
    try {
      reading:
      while (found.length < ChannelSort.wholeTab) {
        var got = 0;
        try {
          await for (final entry in source.next(_page)) {
            got++;
            if (entry is! VideoItem) continue;
            if (known.contains(entry.id)) {
              if (++run >= knownRun) break reading;
              continue;
            }
            run = 0;
            found.add(entry.toJson());
          }
        } finally {
          // Once a page, not once a video: each change redraws the page.
          read.value += got;
        }
        if (got == 0 || source.done) {
          whole = source.done && source.lateError == null;
          break;
        }
      }
    } catch (e) {
      failure = e;
    } finally {
      source.close();
    }
    // Nothing read and nothing kept: the failure is what the page shows.
    if (failure != null && found.isEmpty && known.isEmpty) throw failure;
    final ordered = await _ask(dir == null
        ? {'op': 'order', 'fresh': found, 'order': _order}
        : {'op': 'update', 'dir': dir, 'channel': channel.id, 'tab': _tabName, 'now': _clock().millisecondsSinceEpoch ~/ 1000, 'whole': whole && known.isEmpty, 'fresh': found, 'order': _order});
    // The core gives each entry back as the line it was saved as.
    if (ordered is List) {
      for (final line in ordered) {
        if (line is String) yield line;
      }
      return;
    }
    // Without the core: ordered here, nothing kept.
    final items = [for (final map in found) VideoItem.fromJson(map)];
    final rank = sort.rank!;
    final keyed = [for (var i = 0; i < items.length; i++) (rank(items[i]), i)]..sort((a, b) => a.$1 != b.$1 ? b.$1.compareTo(a.$1) : a.$2.compareTo(b.$2));
    for (final (_, i) in keyed) {
      yield jsonEncode(found[i]);
    }
  }

  Future<Object?> _ask(Map<String, Object?> ask) async {
    try {
      return await _core(ask);
    } catch (_) {
      return null;
    }
  }
}
