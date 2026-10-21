import 'dart:io';

/// The default size cap of the `thumbnails` cache folder.
const defaultThumbnailCapBytes = 512 * 1024 * 1024;

/// The thumbnail cache cap for `PlayerSettings.cacheLimitGb` ([limitGb], in
/// GiB; null means the default).
int thumbnailCapBytes(int? limitGb) => limitGb == null ? defaultThumbnailCapBytes : limitGb * 1024 * 1024 * 1024;

/// Deletes the least recently modified files of [directory] until what is
/// left is at most [capBytes]. Files modified within [recent] of [now] (being
/// written, or just shown) are never deleted, and a file that cannot be
/// deleted is skipped. Returns the bytes freed.
Future<int> trimThumbnails(Directory directory, int capBytes, {DateTime? now, Duration recent = const Duration(minutes: 1)}) async {
  if (!await directory.exists()) return 0;
  final files = <({File file, int size, DateTime modified})>[];
  var total = 0;
  try {
    await for (final item in directory.list(followLinks: false)) {
      if (item is! File) continue;
      try {
        final stat = await item.stat();
        files.add((file: item, size: stat.size, modified: stat.modified));
        total += stat.size;
      } on FileSystemException {
        // Gone meanwhile.
      }
    }
  } on FileSystemException {
    return 0;
  }
  if (total <= capBytes) return 0;
  final newest = (now ?? DateTime.now()).subtract(recent);
  files.sort((a, b) => a.modified.compareTo(b.modified));
  var freed = 0;
  for (final entry in files) {
    if (total - freed <= capBytes) break;
    if (entry.modified.isAfter(newest)) break;
    try {
      await entry.file.delete();
      freed += entry.size;
    } on FileSystemException {
      // In use; the next pass tries again.
    }
  }
  return freed;
}
