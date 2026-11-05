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
