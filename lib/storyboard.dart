// Hover preview thumbnails for the progress bar. YouTube publishes
// "storyboards": sprite sheets of small frames, which yt-dlp lists among the
// formats (format_note "storyboard", ids sb0..sb3, ext mhtml). The idea
// follows PiliNara's video shot preview (lib/plugin/pl_player/models/
// video_shot_data.dart, GPLv3), whose sprite sheets work the same way.

import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:http/http.dart' as http;

/// One sprite sheet: its address and how much of the video it covers.
class StoryboardSheet {
  const StoryboardSheet(this.url, this.duration);
  final String url;
  final Duration duration;
}

/// Where a frame is: the sheet, and its row and column inside that sheet.
class StoryboardTile {
  const StoryboardTile(this.sheet, this.row, this.column);
  final int sheet;
  final int row;
  final int column;
}

class Storyboard {
  const Storyboard({required this.width, required this.height, required this.rows, required this.columns, required this.sheets, required this.interval});

  /// Size of one frame in pixels.
  final int width;
  final int height;
  final int rows;
  final int columns;
  final List<StoryboardSheet> sheets;
  /// Time between two frames.
  final Duration interval;

  int get tilesPerSheet => rows * columns;

  /// The middle storyboard of yt-dlp's `formats`: the widest one up to
  /// [target] pixels (sharp enough for a 160 px preview, small enough to
  /// download quickly), else the smallest above it. Null without any.
  static Storyboard? from(Map<String, dynamic> info, {int target = 200}) {
    final formats = info['formats'];
    if (formats is! List) return null;
    final candidates = <Storyboard>[
      for (final f in formats.whereType<Map>())
        if (f['format_note'] == 'storyboard' || '${f['format_id']}'.startsWith('sb'))
          if (_parse(f) case final board?) board,
    ];
    if (candidates.isEmpty) return null;
    candidates.sort((a, b) => a.width.compareTo(b.width));
    return candidates.lastWhere((c) => c.width <= target, orElse: () => candidates.first);
  }

  static Storyboard? _parse(Map f) {
    final width = f['width'], height = f['height'], rows = f['rows'], columns = f['columns'];
    if (width is! num || height is! num || rows is! num || columns is! num) return null;
    if (width <= 0 || height <= 0 || rows <= 0 || columns <= 0) return null;
    final fragments = f['fragments'];
    if (fragments is! List) return null;
    final sheets = <StoryboardSheet>[
      for (final fragment in fragments.whereType<Map>())
        if (fragment['url'] is String && fragment['duration'] is num && (fragment['duration'] as num) > 0)
          StoryboardSheet(fragment['url'] as String, Duration(microseconds: ((fragment['duration'] as num) * 1e6).round())),
    ];
    if (sheets.isEmpty) return null;
    // yt-dlp's fps is frames per second; without it every sheet but the
    // last holds rows * columns frames.
    final fps = f['fps'];
    final perSheet = (rows * columns).toInt();
    final seconds = fps is num && fps > 0 ? 1 / fps : sheets.first.duration.inMicroseconds / 1e6 / perSheet;
    return Storyboard(
      width: width.toInt(),
      height: height.toInt(),
      rows: rows.toInt(),
      columns: columns.toInt(),
      sheets: sheets,
      interval: Duration(microseconds: max(1, (seconds * 1e6).round())),
    );
  }

  /// The frame shown at [time]; the first or last one outside the video.
  StoryboardTile tileAt(Duration time) {
    var start = Duration.zero;
    for (var i = 0; i < sheets.length; i++) {
      final end = start + sheets[i].duration;
      if (time < end || i == sheets.length - 1) {
        final index = ((time - start).inMicroseconds / interval.inMicroseconds).floor();
        // The last sheet is shorter than a full one.
        final count = min(tilesPerSheet, max(1, (sheets[i].duration.inMicroseconds / interval.inMicroseconds).ceil()));
        final tile = index.clamp(0, count - 1);
        return StoryboardTile(i, tile ~/ columns, tile % columns);
      }
      start = end;
    }
    return const StoryboardTile(0, 0, 0);
  }
}

/// Downloads sprite sheets on demand and keeps the latest few decoded.
class StoryboardSheets {
  StoryboardSheets(this._http, {this.keep = 6});

  final http.Client _http;
  final int keep;
  final _images = <String, Future<ui.Image?>>{};

  /// The decoded sheet at [url]; null when it could not be fetched.
  Future<ui.Image?> sheet(String url) {
    final cached = _images.remove(url);
    if (cached != null) return _images[url] = cached;
    final future = _load(url);
    _images[url] = future;
    while (_images.length > keep) {
      // Not disposed: a preview may still be drawing it, and the garbage
      // collector frees it once nothing does.
      _images.remove(_images.keys.first);
    }
    // A failure is not kept, so hovering again tries again.
    unawaited(future.then((image) {
      if (image == null && identical(_images[url], future)) _images.remove(url);
    }));
    return future;
  }

  Future<ui.Image?> _load(String url) async {
    try {
      final response = await _http.get(Uri.parse(url)).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200 || response.bodyBytes.isEmpty) return null;
      final codec = await ui.instantiateImageCodec(response.bodyBytes);
      final frame = await codec.getNextFrame();
      codec.dispose();
      return frame.image;
    } catch (_) {
      return null;
    }
  }

  void clear() => _images.clear();
}
