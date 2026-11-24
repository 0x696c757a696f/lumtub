import '../l10n/l10n.dart';
import '../library_store.dart' show WatchProgress;
import '../models.dart';
import 'pages/watch_stats_page.dart' show watchDuration;

/// 共 3 小时 20 分 for [items], with 还剩 … when [progressOf] knows what was
/// watched of them. "至少" when some lengths are unknown or [partial] (more
/// to load). Null when no length is known.
String? playlistLength(List<VideoItem> items, {WatchProgress? Function(String id)? progressOf, bool partial = false}) {
  var total = 0;
  var left = 0;
  var unknown = partial;
  for (final item in items) {
    final seconds = item.duration;
    if (seconds == null || seconds <= 0) {
      unknown = true;
      continue;
    }
    total += seconds;
    final progress = progressOf?.call(item.id);
    left += progress == null ? seconds : progress.finished ? 0 : (seconds - progress.position.inSeconds).clamp(0, seconds);
  }
  if (total == 0) return null;
  final length = unknown ? tr('At least {0}', [watchDuration(total)]) : tr('{0} in total', [watchDuration(total)]);
  if (progressOf == null || left == total) return length;
  return left == 0 ? tr('{0} · all watched', [length]) : tr('{0} · {1} left', [length, watchDuration(left)]);
}

/// What a playlist page shows of [source]: a copy of it, the same last to
/// first when [reversed], and its [playlistLength]. The page rebuilds on
/// every notify and a list runs to thousands of videos, so this is kept
/// while [key] (what the list comes from and its state) stays; the time
/// left follows saved positions, which change without a notify, so it is
/// also worked out again every half minute.
({List<VideoItem> own, List<VideoItem> items, String? length}) playlistView(Object? key, List<VideoItem> source,
    {required bool reversed, WatchProgress? Function(String id)? progressOf, bool partial = false}) {
  final full = (key, source, source.length, reversed, partial, DateTime.now().millisecondsSinceEpoch ~/ 30000);
  if (_playlistView case (final known, final kept) when known == full) return kept;
  final own = List<VideoItem>.of(source);
  final items = reversed ? own.reversed.toList() : own;
  final kept = (own: own, items: items, length: playlistLength(items, progressOf: progressOf, partial: partial));
  _playlistView = (full, kept);
  return kept;
}

(Object, ({List<VideoItem> own, List<VideoItem> items, String? length}))? _playlistView;
