import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'models.dart';
import 'thumbnail_cache.dart';

/// Tells a vertical video that search listings give no frame size for by its
/// thumbnail: YouTube fills the sides of a portrait frame in a 16:9
/// thumbnail with black or a blur, so the sides are flat while the middle
/// third holds the picture. Verdicts are kept in a file.
abstract final class PortraitThumbnails {
  static final LinkedHashMap<String, bool> _known = LinkedHashMap();
  static File? _file;
  static Timer? _save;

  /// Verdicts kept; the oldest go first.
  static const keep = 20000;

  /// The thumbnail is decoded at this size: hqdefault is 4:3, with the
  /// 16:9 frame between bars above and below.
  static const width = 160, height = 120;

  /// The sides' detail, as a share of the middle's, below which they are
  /// bars. Measured on real thumbnails: portrait ones 0.08-0.33, ordinary
  /// ones from 0.39.
  static const flatSides = 0.35;

  /// The middle's least detail; below it the whole picture is flat, as a
  /// title card, and nothing can be told.
  static const minDetail = 12.0;

  static Future<void> configure(File file) async {
    _file = file;
    try {
      final saved = jsonDecode(await file.readAsString());
      if (saved is Map) {
        for (final MapEntry(:key, :value) in saved.entries) {
          if (key is String && value is bool) _known.putIfAbsent(key, () => value);
        }
      }
    } catch (_) {}
  }

  static bool? known(String id) => _known[id];

  /// Whether [id]'s thumbnail shows a portrait frame; false when it cannot
  /// be loaded.
  static Future<bool> check(String id, Directory thumbnails) async {
    if (_known[id] case final verdict?) return verdict;
    final Uint8List bytes;
    try {
      bytes = await CachedThumbnail('https://i.ytimg.com/vi/$id/hqdefault.jpg', CachedThumbnail.fileFor(thumbnails, id)).bytes();
    } catch (_) {
      return false;
    }
    final verdict = await pillarboxed(bytes);
    if (verdict != null) _remember(id, verdict);
    return verdict ?? false;
  }

  static void _remember(String id, bool verdict) {
    _known.remove(id);
    _known[id] = verdict;
    while (_known.length > keep) {
      _known.remove(_known.keys.first);
    }
    if (_file == null) return;
    _save?.cancel();
    _save = Timer(const Duration(seconds: 5), () {
      final file = _file;
      if (file != null) unawaited(file.writeAsString(jsonEncode(_known)).then((_) {}, onError: (_) {}));
    });
  }

  /// Decodes [jpeg] small and judges it; null when it cannot be decoded.
  static Future<bool?> pillarboxed(Uint8List jpeg) async {
    try {
      final codec = await ui.instantiateImageCodec(jpeg, targetWidth: width, targetHeight: height);
      final frame = await codec.getNextFrame();
      codec.dispose();
      final data = await frame.image.toByteData();
      frame.image.dispose();
      return data == null ? null : judge(data.buffer.asUint8List(), width, height);
    } catch (_) {
      return null;
    }
  }

  /// Whether the [w]×[h] RGBA picture of a 4:3 thumbnail has flat sides
  /// around a detailed middle third.
  static bool judge(Uint8List rgba, int w, int h) {
    final top = h ~/ 8, bottom = h - h ~/ 8;
    final luma = Float32List(w * h);
    for (var i = 0; i < w * h; i++) {
      luma[i] = 0.299 * rgba[i * 4] + 0.587 * rgba[i * 4 + 1] + 0.114 * rgba[i * 4 + 2];
    }
    // Detail of a column range: horizontal plus vertical change per pixel.
    double detail(int from, int to) {
      var sum = 0.0;
      for (var y = top; y < bottom; y++) {
        for (var x = from; x < to; x++) {
          final i = y * w + x;
          if (x + 1 < w) sum += (luma[i + 1] - luma[i]).abs();
          if (y + 1 < bottom) sum += (luma[i + w] - luma[i]).abs();
        }
      }
      return sum / ((bottom - top) * (to - from));
    }

    // A 9:16 frame in 16:9 spans the middle 32%; the sides are measured
    // clear of its edges.
    final middle = detail(w * 36 ~/ 100, w * 64 ~/ 100);
    if (middle < minDetail) return false;
    final sides = (detail(w * 3 ~/ 100, w * 29 ~/ 100) + detail(w * 71 ~/ 100, w * 97 ~/ 100)) / 2;
    return sides < middle * flatSides;
  }

  /// [lines] of a listing without the videos whose thumbnails are
  /// portrait, in order, with up to [parallel] thumbnails looked at once.
  static Stream<String> drop(Stream<String> lines, Future<bool> Function(String id) portrait, {int parallel = 6}) {
    final out = StreamController<String>();
    final queue = Queue<_Held>();
    StreamSubscription<String>? source;
    var paused = false, ended = false;
    void flush() {
      while (queue.isNotEmpty && queue.first.done) {
        final held = queue.removeFirst();
        if (!held.portrait) out.add(held.line);
      }
      if (out.isClosed) return;
      if (ended && queue.isEmpty) {
        unawaited(out.close());
        return;
      }
      final full = queue.length >= parallel;
      if (full && !paused) {
        paused = true;
        source?.pause();
      } else if (!full && paused) {
        paused = false;
        source?.resume();
      }
    }

    out.onListen = () {
      source = lines.listen(
        (line) {
          final held = _Held(line);
          queue.add(held);
          final item = parseListingEntry(line);
          if (item is VideoItem) {
            portrait(item.id).then((v) => v, onError: (_) => false).then((v) {
              held
                ..portrait = v
                ..done = true;
              flush();
            });
          } else {
            held.done = true;
          }
          flush();
        },
        onError: out.addError,
        onDone: () {
          ended = true;
          flush();
        },
      );
    };
    out.onCancel = () => source?.cancel();
    return out.stream;
  }

  static void reset() => _known.clear();
}

class _Held {
  _Held(this.line);
  final String line;
  bool done = false;
  bool portrait = false;
}
