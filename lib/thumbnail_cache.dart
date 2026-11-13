import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:http/http.dart' as http;

import 'native_http.dart';

/// Loads a thumbnail from Lumtub's `thumbnails` cache folder, downloading it
/// there on first use. Scrolling back or reopening the app then needs no
/// network request.
@immutable
class CachedThumbnail extends ImageProvider<CachedThumbnail> {
  const CachedThumbnail(this.url, this.file, {this.fallback});

  final String url;
  final File file;
  /// Loaded instead when [url] fails, such as YouTube's own thumbnail
  /// when DeArrow's frame is not ready.
  final CachedThumbnail? fallback;

  static final http.Client _client = appHttpClient();
  static final Random _random = Random();

  /// The cache file for [videoId]; ids are validated YouTube ids, so they are
  /// safe as file names.
  /// Sizes other than the default `hqdefault` are cached under their own
  /// name, so switching sizes never shows a stale image.
  static File fileFor(Directory directory, String videoId, [String size = 'hqdefault']) =>
      File('${directory.path}${Platform.pathSeparator}$videoId${size == 'hqdefault' ? '' : '_$size'}.jpg');

  @override
  Future<CachedThumbnail> obtainKey(ImageConfiguration configuration) => SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(CachedThumbnail key, ImageDecoderCallback decode) {
    late final _ThumbnailCompleter completer;
    completer = _ThumbnailCompleter(codec: _load(decode, () => completer.wanted), debugLabel: url);
    return completer;
  }

  Future<ui.Codec> _load(ImageDecoderCallback decode, bool Function() wanted) async {
    final Uint8List bytes;
    try {
      bytes = await _bytes(wanted);
    } on ThumbnailDropped {
      rethrow;
    } catch (_) {
      final fallback = this.fallback;
      if (fallback == null) rethrow;
      return fallback._load(decode, wanted);
    }
    return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
  }

  /// Addresses that failed lately, and when. Flutter forgets an image that
  /// failed, so a card scrolled back into view would ask again; a refused
  /// address waits ten minutes, one the network failed half a minute.
  static final _failed = <String, (DateTime, Duration)>{};

  static final _youtubeJpeg = RegExp(r'^https://i\.ytimg\.com/vi/([\w-]+)/(\w+)\.jpg$');

  /// What to ask for, in order, until one is not a 404. YouTube's WebP
  /// copy of a thumbnail is about a third smaller than the JPEG and every
  /// platform's decoder reads it; a few old videos lack it. The larger
  /// sizes exist only for some videos; hqdefault always does.
  static List<String> candidates(String url) {
    final match = _youtubeJpeg.firstMatch(url);
    if (match == null) return [url];
    final id = match[1]!;
    final names = [match[2]!, if (const {'maxresdefault', 'sddefault'}.contains(match[2])) 'hqdefault'];
    return [
      for (final name in names) ...['https://i.ytimg.com/vi_webp/$id/$name.webp', 'https://i.ytimg.com/vi/$id/$name.jpg'],
    ];
  }

  /// The picture's bytes, from the cache file or downloaded into it.
  Future<Uint8List> bytes() => _bytes(_always);

  static bool _always() => true;

  Future<Uint8List> _bytes(bool Function() wanted) async {
    try {
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        if (bytes.isNotEmpty) {
          _touch();
          return bytes;
        }
      }
    } on FileSystemException {
      // Downloaded again below.
    }
    if (_failed[url] case (final at, final wait) when DateTime.now().difference(at) < wait) {
      throw HttpException('Thumbnail failed lately', uri: Uri.parse(url));
    }
    try {
      var status = 0;
      Uint8List? body;
      await slot(wanted);
      try {
        for (final address in candidates(url)) {
          (status, body) = await fetch(_client, Uri.parse(address)).timeout(const Duration(seconds: 10));
          if (status != 404) break;
        }
      } finally {
        free();
      }
      if (status != 200 || body == null || body.isEmpty) {
        _remember(const Duration(minutes: 10));
        throw HttpException('Thumbnail HTTP $status', uri: Uri.parse(url));
      }
      _failed.remove(url);
      await _store(body);
      return body;
    } on HttpException {
      rethrow;
    } on ThumbnailDropped {
      rethrow;
    } catch (_) {
      _remember(const Duration(seconds: 30));
      rethrow;
    }
  }

  /// The largest thumbnail read; YouTube's biggest are well under 1 MiB.
  static const maxBytes = 4 << 20;

  /// Downloads at a time, so a fast scroll does not open dozens at once.
  static const _parallel = 6;
  static int _running = 0;
  static final _waiting = <(Completer<void>, bool Function())>[];

  /// Waits for a download slot. A picture no one [wanted] any more by its
  /// turn, as its card scrolled off screen, is dropped with
  /// [ThumbnailDropped] instead of taking a slot from one on screen.
  @visibleForTesting
  static Future<void> slot(bool Function() wanted) {
    if (_running < _parallel) {
      _running++;
      return Future.value();
    }
    final turn = Completer<void>();
    _waiting.add((turn, wanted));
    return turn.future;
  }

  @visibleForTesting
  static void free() {
    while (_waiting.isNotEmpty) {
      final (turn, wanted) = _waiting.removeAt(0);
      if (wanted()) return turn.complete();
      turn.completeError(const ThumbnailDropped());
    }
    _running--;
  }

  /// [address]'s status and body; a body over [maxBytes] is cut off and
  /// read as a failure.
  @visibleForTesting
  static Future<(int, Uint8List?)> fetch(http.Client client, Uri address) async {
    final response = await client.send(http.Request('GET', address));
    if (response.statusCode != 200 || (response.contentLength ?? 0) > maxBytes) {
      unawaited(response.stream.listen(null).cancel());
      return (response.statusCode == 200 ? 413 : response.statusCode, null);
    }
    final body = BytesBuilder(copy: false);
    await for (final piece in response.stream) {
      body.add(piece);
      if (body.length > maxBytes) return (413, null);
    }
    return (200, body.takeBytes());
  }

  /// Marks the file as used, at most once a day, so trimming drops the
  /// pictures not seen for longest rather than the oldest downloads.
  void _touch() {
    unawaited(() async {
      try {
        final now = DateTime.now();
        if (now.difference(await file.lastModified()) > const Duration(days: 1)) await file.setLastModified(now);
      } on FileSystemException {
        // Only the order of trimming suffers.
      }
    }());
  }

  void _remember(Duration wait) {
    _failed.remove(url);
    if (_failed.length >= 500) _failed.remove(_failed.keys.first);
    _failed[url] = (DateTime.now(), wait);
  }

  /// Writes through a unique temporary file so two cards loading the same
  /// video never leave a half-written image behind. Failures only skip caching.
  Future<void> _store(Uint8List bytes) async {
    final temp = File('${file.path}.${_random.nextInt(1 << 32)}.part');
    try {
      await file.parent.create(recursive: true);
      await temp.writeAsBytes(bytes);
      await temp.rename(file.path);
    } on FileSystemException {
      try {
        if (await temp.exists()) await temp.delete();
      } on FileSystemException {
        // Leave it for the next cache clean-up.
      }
    }
  }

  @override
  bool operator ==(Object other) => other is CachedThumbnail && other.url == url && other.file.path == file.path;

  @override
  int get hashCode => Object.hash(url, file.path);
}

/// A thumbnail download skipped because no card shows it any more. The
/// image cache forgets it, so a card scrolled back loads it again.
class ThumbnailDropped implements Exception {
  const ThumbnailDropped();

  @override
  String toString() => 'Thumbnail no longer shown';
}

/// Counts who waits for the picture. The image cache itself listens first
/// to every load, until its first frame, so the picture is wanted only
/// while someone else (a card, a precache) listens too.
class _ThumbnailCompleter extends MultiFrameImageStreamCompleter {
  _ThumbnailCompleter({required super.codec, required String super.debugLabel}) : super(scale: 1.0);

  ImageStreamListener? _cache;
  bool _seen = false;
  int _others = 0;

  bool get wanted => _others > 0;

  @override
  void addListener(ImageStreamListener listener) {
    if (_seen) {
      _others++;
    } else {
      _seen = true;
      _cache = listener;
    }
    super.addListener(listener);
  }

  @override
  void removeListener(ImageStreamListener listener) {
    if (_cache != null && listener == _cache) {
      _cache = null;
    } else if (_others > 0) {
      _others--;
    }
    super.removeListener(listener);
  }
}
