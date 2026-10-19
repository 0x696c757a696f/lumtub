import 'dart:convert';

class VideoItem {
  final String id;
  final String title;
  final String channel;
  final int? duration;
  final String url;
  final int? viewCount;
  /// The channel's `UC…` id, when the source listed it.
  final String? channelId;
  /// Upload time, known for subscription feed entries.
  final DateTime? published;

  const VideoItem({
    required this.id,
    required this.title,
    required this.channel,
    this.duration,
    required this.url,
    this.viewCount,
    this.channelId,
    this.published,
  });

  /// This video credited to [ref], keeping the known name when [ref] has none.
  VideoItem withChannel(ChannelRef ref) => VideoItem(
        id: id,
        title: title,
        channel: channel.isNotEmpty ? channel : ref.name,
        duration: duration,
        url: url,
        viewCount: viewCount,
        channelId: ref.id,
        published: published,
      );

  ChannelRef? get channelRef => channelId == null ? null : ChannelRef(channelId!, channel);

  /// The thumbnail size to load, a YouTube file name such as `hqdefault`;
  /// set from the appearance settings.
  static String thumbnailFile = 'hqdefault';

  String get thumbnail => 'https://i.ytimg.com/vi/$id/$thumbnailFile.jpg';

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
        if (viewCount != null) 'view_count': viewCount,
        if (channelId != null) 'channel_id': channelId,
        if (published != null) 'published': published!.toUtc().toIso8601String(),
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
    final views = map['view_count'];
    final channelId = map['channel_id']?.toString();
    return VideoItem(
      id: id,
      title: map['title']?.toString() ?? 'Untitled video',
      channel: name.toString(),
      duration: value is num ? value.toInt() : null,
      url: 'https://www.youtube.com/watch?v=$id',
      viewCount: views is num ? views.toInt() : null,
      channelId: channelId != null && ChannelRef.isValidId(channelId) ? channelId : null,
      published: DateTime.tryParse(map['published']?.toString() ?? ''),
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

/// A YouTube channel, identified by its `UC…` id.
class ChannelRef {
  const ChannelRef(this.id, this.name);
  final String id;
  final String name;

  String get url => 'https://www.youtube.com/channel/$id';

  static bool isValidId(String id) => RegExp(r'^UC[\w-]{22}$').hasMatch(id);

  Map<String, dynamic> toJson() => {'id': id, 'name': name};

  static ChannelRef? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id']?.toString() ?? '';
    return isValidId(id) ? ChannelRef(id, raw['name']?.toString() ?? '') : null;
  }

  @override
  bool operator ==(Object other) => other is ChannelRef && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// A channel found by a search, with what the result listed about it.
class ChannelResult {
  const ChannelResult(this.ref, {this.subscribers, this.handle, this.avatar, this.description = ''});
  final ChannelRef ref;
  /// YouTube's own subscriber text, such as "123万位订阅者"; search results
  /// often carry the handle in its place.
  final String? subscribers;
  final String? handle;
  final String? avatar;
  final String description;

  /// Reads a flat `--dump-json` channel entry, or returns null for
  /// anything else.
  static ChannelResult? tryParse(Map<String, dynamic> map) {
    final id = (map['channel_id'] ?? map['id'])?.toString() ?? '';
    if (map['ie_key'] != 'YoutubeTab' || !ChannelRef.isValidId(id)) return null;
    final followers = map['channel_follower_count'];
    final thumbnails = map['thumbnails'];
    String? avatar;
    if (thumbnails is List) {
      for (final t in thumbnails.whereType<Map>()) {
        final url = t['url']?.toString() ?? '';
        if (url.isNotEmpty) avatar = url.startsWith('//') ? 'https:$url' : url;
      }
    }
    return ChannelResult(
      ChannelRef(id, (map['channel'] ?? map['title'] ?? '').toString()),
      subscribers: followers is num ? '${formatCount(followers.toInt())} 位订阅者' : null,
      handle: map['uploader_id']?.toString(),
      avatar: avatar != null && avatar.startsWith('https://') ? avatar : null,
      description: map['description']?.toString() ?? '',
    );
  }
}

/// One entry of a listing: a [VideoItem] or a [ChannelResult].
Object? parseListingEntry(String line) {
  final Object? data;
  try {
    data = jsonDecode(line);
  } catch (_) {
    return null;
  }
  if (data is! Map<String, dynamic>) return null;
  final channel = ChannelResult.tryParse(data);
  if (channel != null) return channel;
  try {
    return VideoItem.fromJson(data);
  } catch (_) {
    return null;
  }
}

/// Formats a count the way Chinese YouTube does: 9,999 / 1.2万 / 3.4亿.
String formatCount(int value) {
  if (value < 10000) return '$value';
  if (value < 100000000) return '${_trim(value / 10000)}万';
  return '${_trim(value / 100000000)}亿';
}

String _trim(double value) => value >= 100 ? value.toStringAsFixed(0) : value.toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '');

/// Metadata shown on the watch page, fetched separately from playback.
class VideoDetails {
  final String title;
  final String channel;
  final String? channelUrl;
  final String? channelId;
  final DateTime? uploadDate;
  final int? viewCount;
  final int? likeCount;
  final String description;

  const VideoDetails({
    required this.title,
    required this.channel,
    this.channelUrl,
    this.channelId,
    this.uploadDate,
    this.viewCount,
    this.likeCount,
    this.description = '',
  });

  factory VideoDetails.fromJson(Map<String, dynamic> map) {
    int? number(String key) => map[key] is num ? (map[key] as num).toInt() : null;
    final date = map['upload_date']?.toString() ?? '';
    final match = RegExp(r'^(\d{4})(\d{2})(\d{2})$').firstMatch(date);
    return VideoDetails(
      title: map['title']?.toString() ?? '',
      channel: (map['channel'] ?? map['uploader'] ?? '').toString(),
      channelUrl: map['channel_url']?.toString(),
      channelId: ChannelRef.isValidId(map['channel_id']?.toString() ?? '') ? map['channel_id'].toString() : null,
      uploadDate: match == null ? null : DateTime(int.parse(match[1]!), int.parse(match[2]!), int.parse(match[3]!)),
      viewCount: number('view_count'),
      likeCount: number('like_count'),
      description: map['description']?.toString() ?? '',
    );
  }
}
