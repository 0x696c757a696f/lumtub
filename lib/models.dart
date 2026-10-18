import 'dart:convert';

class VideoItem {
  final String id;
  final String title;
  final String channel;
  final int? duration;
  final String url;

  const VideoItem({
    required this.id,
    required this.title,
    required this.channel,
    this.duration,
    required this.url,
  });

  String get thumbnail => 'https://i.ytimg.com/vi/$id/hqdefault.jpg';

  String get durationLabel {
    if (duration == null) return '';
    final d = Duration(seconds: duration!);
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '${d.inMinutes}:$seconds';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'channel': channel,
        'duration': duration,
        'url': url,
      };

  factory VideoItem.fromJson(Map<String, dynamic> map) {
    final raw = map['id']?.toString() ?? '';
    // yt-dlp flat playlist results normally expose an 11-character YouTube ID.
    final id = RegExp(r'^[\w-]{11}$').hasMatch(raw)
        ? raw
        : (RegExp(r'[?&]v=([\w-]{11})').firstMatch(map['url']?.toString() ?? '')?.group(1) ?? '');
    if (id.isEmpty) throw const FormatException('Missing YouTube video ID');
    final name = map['channel'] ?? map['uploader'] ?? map['uploader_id'] ?? '';
    final value = map['duration'];
    return VideoItem(
      id: id,
      title: map['title']?.toString() ?? 'Untitled video',
      channel: name.toString(),
      duration: value is num ? value.toInt() : null,
      url: 'https://www.youtube.com/watch?v=$id',
    );
  }

  static List<VideoItem> fromJsonLines(String stdout) {
    final results = <VideoItem>[];
    final seen = <String>{};
    for (final line in const LineSplitter().convert(stdout)) {
      final item = tryParseLine(line);
      if (item != null && seen.add(item.id)) results.add(item);
    }
    return results;
  }

  /// Parses one `--dump-json` line, or returns null for notices and
  /// non-video entries that yt-dlp may also print.
  static VideoItem? tryParseLine(String line) {
    try {
      final data = jsonDecode(line);
      return data is Map<String, dynamic> ? VideoItem.fromJson(data) : null;
    } catch (_) {
      return null;
    }
  }
}
