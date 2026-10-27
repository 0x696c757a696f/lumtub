import 'dart:convert';

import 'l10n/l10n.dart';

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
  /// yt-dlp's live_status: is_live, is_upcoming or was_live; null otherwise.
  final String? liveStatus;
  /// Scheduled local start time for an upcoming stream, reported by yt-dlp.
  final DateTime? scheduledStart;
  /// Frame size, when the source listed it; height over width is vertical.
  final int? width;
  final int? height;
  /// The start of the description, when listed: auto-generated music
  /// uploads say "Provided to YouTube by".
  final String? description;
  /// Listed as a Short (a /shorts/ address), whatever its length.
  final bool isShortListing;

  bool get isLive => liveStatus == 'is_live';
  bool get isUpcoming => liveStatus == 'is_upcoming';

  const VideoItem({
    required this.id,
    required this.title,
    required this.channel,
    this.duration,
    required this.url,
    this.viewCount,
    this.channelId,
    this.published,
    this.liveStatus,
    this.scheduledStart,
    this.width,
    this.height,
    this.description,
    this.isShortListing = false,
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
        liveStatus: liveStatus,
        scheduledStart: scheduledStart,
        width: width,
        height: height,
        description: description,
        isShortListing: isShortListing,
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
        if (liveStatus != null) 'live_status': liveStatus,
        if (scheduledStart != null) 'scheduled_start': scheduledStart!.toUtc().toIso8601String(),
        if (width != null) 'width': width,
        if (height != null) 'height': height,
        if (description != null) 'description': description,
        if (isShortListing) 'is_short': true,
      };

  // Compiled once: every listing entry and saved item comes through here.
  static final _videoId = RegExp(r'^[\w-]{11}$');
  static final _watchUrlId = RegExp(r'[?&]v=([\w-]{11})');

  factory VideoItem.fromJson(Map<String, dynamic> map) {
    final raw = map['id']?.toString() ?? '';
    // yt-dlp flat playlist results normally expose an 11-character YouTube ID.
    final id = _videoId.hasMatch(raw)
        ? raw
        : (_watchUrlId.firstMatch(map['url']?.toString() ?? '')?.group(1) ?? '');
    if (id.isEmpty) throw const FormatException('Missing YouTube video ID');
    final name = map['channel'] ?? map['uploader'] ?? map['uploader_id'] ?? '';
    final value = map['duration'];
    final views = map['view_count'];
    final channelId = map['channel_id']?.toString();
    final width = map['width'];
    final height = map['height'];
    final description = map['description'];
    final listed = '${map['original_url'] ?? ''} ${map['webpage_url'] ?? ''}';
    final liveStatus = const {'is_live', 'is_upcoming', 'was_live'}.contains(map['live_status']) ? map['live_status'] as String : null;
    DateTime? unixTime(Object? value) {
      final seconds = value is num ? value.toInt() : int.tryParse('${value ?? ''}');
      return seconds == null || seconds <= 0 ? null : DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true).toLocal();
    }
    final savedScheduledStart = DateTime.tryParse(map['scheduled_start']?.toString() ?? '')?.toLocal();
    return VideoItem(
      id: id,
      title: map['title']?.toString() ?? 'Untitled video',
      channel: name.toString(),
      duration: value is num ? value.toInt() : null,
      url: 'https://www.youtube.com/watch?v=$id',
      viewCount: views is num ? views.toInt() : null,
      channelId: channelId != null && ChannelRef.isValidId(channelId) ? channelId : null,
      published: DateTime.tryParse(map['published']?.toString() ?? ''),
      liveStatus: liveStatus,
      scheduledStart: savedScheduledStart ?? (liveStatus == 'is_upcoming' ? unixTime(map['release_timestamp']) ?? unixTime(map['timestamp']) : null),
      width: width is num ? width.toInt() : null,
      height: height is num ? height.toInt() : null,
      description: description is String && description.isNotEmpty ? description.substring(0, description.length < 120 ? description.length : 120) : null,
      isShortListing: map['is_short'] == true || listed.contains('/shorts/'),
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
  const ChannelRef(this.id, this.name, [this.avatar]);
  final String id;
  final String name;
  /// The channel's picture, when a subscription import or search listed one.
  final String? avatar;

  String get url => 'https://www.youtube.com/channel/$id';

  static bool isValidId(String id) => _id.hasMatch(id);
  static final _id = RegExp(r'^UC[\w-]{22}$');

  /// [raw] as an https picture address, or null; the protocol-relative and
  /// plain http forms some responses use are upgraded.
  static String? avatarUrl(Object? raw) {
    if (raw is! String) return null;
    final url = raw.startsWith('//') ? 'https:$raw' : raw.startsWith('http://') ? 'https://${raw.substring(7)}' : raw;
    return url.startsWith('https://') ? url : null;
  }

  Map<String, dynamic> toJson() => {'id': id, 'name': name, if (avatar != null) 'avatar': avatar};

  static ChannelRef? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id']?.toString() ?? '';
    return isValidId(id) ? ChannelRef(id, raw['name']?.toString() ?? '', avatarUrl(raw['avatar'])) : null;
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
    if (!_isTab(map) || !ChannelRef.isValidId(id)) return null;
    final followers = map['channel_follower_count'];
    final thumbnails = map['thumbnails'];
    String? avatar;
    if (thumbnails is List) {
      for (final t in thumbnails.whereType<Map>()) {
        final url = t['url']?.toString() ?? '';
        if (url.isNotEmpty) avatar = url;
      }
    }
    return ChannelResult(
      ChannelRef(id, (map['channel'] ?? map['title'] ?? '').toString()),
      subscribers: followers is num ? tr('{0} 位订阅者', [formatCount(followers.toInt())]) : null,
      handle: map['uploader_id']?.toString(),
      avatar: ChannelRef.avatarUrl(avatar),
      description: map['description']?.toString() ?? '',
    );
  }
}

/// A YouTube playlist found by a search or on a channel's playlists tab.
class PlaylistResult {
  const PlaylistResult({required this.id, required this.title, this.channel = '', this.count, this.thumbnail});
  final String id;
  final String title;
  final String channel;
  final int? count;
  final String? thumbnail;

  String get url => 'https://www.youtube.com/playlist?list=$id';

  static bool isValidId(String id) => _id.hasMatch(id) && !ChannelRef.isValidId(id);
  static final _id = RegExp(r'^[\w-]{10,64}$');

  /// Reads a flat `--dump-json` playlist entry, or returns null.
  static PlaylistResult? tryParse(Map<String, dynamic> map) {
    if (!_isTab(map)) return null;
    final url = map['url']?.toString() ?? '';
    final id = Uri.tryParse(url)?.queryParameters['list'] ?? map['id']?.toString() ?? '';
    if (!url.contains('list=') || !isValidId(id)) return null;
    final count = map['playlist_count'];
    String? thumbnail;
    final thumbnails = map['thumbnails'];
    if (thumbnails is List) {
      for (final t in thumbnails.whereType<Map>()) {
        final u = t['url']?.toString() ?? '';
        if (u.isNotEmpty) thumbnail = u.startsWith('//') ? 'https:$u' : u;
      }
    }
    return PlaylistResult(
      id: id,
      title: map['title']?.toString() ?? tr('播放列表'),
      channel: (map['channel'] ?? map['uploader'] ?? '').toString(),
      count: count is num ? count.toInt() : null,
      thumbnail: thumbnail != null && thumbnail.startsWith('https://') ? thumbnail : null,
    );
  }
}

/// Whether a flat entry is a channel or playlist page. yt-dlp now reports
/// `extractor_key`; older versions reported `ie_key`.
bool _isTab(Map<String, dynamic> map) => (map['extractor_key'] ?? map['ie_key']) == 'YoutubeTab';

/// One entry of a listing: a [VideoItem], [ChannelResult] or [PlaylistResult].
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
  final playlist = PlaylistResult.tryParse(data);
  if (playlist != null) return playlist;
  try {
    return VideoItem.fromJson(data);
  } catch (_) {
    return null;
  }
}

/// Formats a count the way Chinese YouTube does: 9,999 / 1.2万 / 3.4亿.
String formatCount(int value) {
  if (!currentLanguage.isChinese) {
    if (value < 1000) return '$value';
    if (value < 1000000) return '${_trim(value / 1000)}K';
    if (value < 1000000000) return '${_trim(value / 1000000)}M';
    return '${_trim(value / 1000000000)}B';
  }
  if (value < 10000) return '$value';
  if (value < 100000000) return tr('{0}万', [_trim(value / 10000)]);
  return tr('{0}亿', [_trim(value / 100000000)]);
}

String _trim(double value) => value >= 100 ? value.toStringAsFixed(0) : value.toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '');

/// Metadata shown on the watch page, fetched separately from playback.
/// A titled part of a video, from the uploader's chapter list.
class Chapter {
  const Chapter(this.start, this.end, this.title);
  final Duration start;
  /// [Duration.zero] when unknown; the next chapter's start then ends it.
  final Duration end;
  final String title;

  /// yt-dlp's `chapters`, in order, without unusable entries.
  static List<Chapter> listFrom(Object? raw) {
    if (raw is! List) return const [];
    Duration? seconds(Object? value) => value is num && value >= 0 ? Duration(milliseconds: (value * 1000).round()) : null;
    final chapters = [
      for (final entry in raw.whereType<Map>())
        if (seconds(entry['start_time']) case final start?)
          Chapter(start, seconds(entry['end_time']) ?? Duration.zero, entry['title']?.toString().trim() ?? ''),
    ]..sort((a, b) => a.start.compareTo(b.start));
    return chapters.length < 2 ? const [] : chapters;
  }

  /// The chapter [position] is in, or null before the first one.
  static Chapter? at(List<Chapter> chapters, Duration position) {
    Chapter? found;
    for (final chapter in chapters) {
      if (chapter.start > position) break;
      found = chapter;
    }
    return found;
  }
}

class VideoDetails {
  final String title;
  final String channel;
  final String? channelUrl;
  final String? channelId;
  final DateTime? uploadDate;
  final int? viewCount;
  final int? likeCount;
  final String description;
  final List<Chapter> chapters;
  /// Every subtitle YouTube offers: uploaded ones, then automatic captions
  /// and their machine translations.
  final List<SubtitleOption> subtitles;
  /// When a live stream or premiere that has not started is scheduled to.
  final DateTime? scheduledStart;
  /// The language the video is in, as yt-dlp tags it, when known.
  final String? language;

  const VideoDetails({
    required this.title,
    required this.channel,
    this.channelUrl,
    this.channelId,
    this.uploadDate,
    this.viewCount,
    this.likeCount,
    this.description = '',
    this.chapters = const [],
    this.subtitles = const [],
    this.scheduledStart,
    this.language,
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
      chapters: Chapter.listFrom(map['chapters']),
      subtitles: SubtitleOption.listFrom(map['subtitles'], map['automatic_captions']),
      scheduledStart: map['live_status'] == 'is_upcoming' && map['release_timestamp'] is num
          ? DateTime.fromMillisecondsSinceEpoch((map['release_timestamp'] as num).toInt() * 1000)
          : null,
      language: map['language'] is String && (map['language'] as String).isNotEmpty ? map['language'] as String : null,
    );
  }

  /// These details with YouTube's [title] and [description] in the
  /// interface language. Chapters come from the description's timestamps,
  /// so where the translated one lists the same times, theirs are renamed.
  VideoDetails localized(String title, String description, {int? likes}) {
    if (title.isEmpty || (title == this.title && description == this.description && (likes == null || likeCount != null))) return this;
    final names = <int, String>{};
    for (final line in const LineSplitter().convert(description)) {
      final match = _chapterLine.firstMatch(line);
      if (match == null) continue;
      final seconds = int.parse(match[1] ?? '0') * 3600 + int.parse(match[2]!) * 60 + int.parse(match[3]!);
      names.putIfAbsent(seconds, () => match[4]!.trim());
    }
    return VideoDetails(
      title: title,
      channel: channel,
      channelUrl: channelUrl,
      channelId: channelId,
      uploadDate: uploadDate,
      viewCount: viewCount,
      likeCount: likeCount ?? likes,
      description: description.isEmpty ? this.description : description,
      chapters: [
        for (final c in chapters) Chapter(c.start, c.end, names[c.start.inSeconds] ?? c.title),
      ],
      subtitles: subtitles,
      scheduledStart: scheduledStart,
      language: language,
    );
  }

  static final _chapterLine = RegExp(r'^\s*[\[(]?(?:(\d{1,2}):)?(\d{1,2}):(\d{2})[\])]?\s*[-–—:|·]?\s*(\S.*)$');
}

/// A subtitle track of a video that can be added to the player by URL.
class SubtitleOption {
  const SubtitleOption({required this.language, required this.name, required this.url, this.kind = SubtitleKind.uploaded});
  final String language;
  final String name;
  final String url;
  final SubtitleKind kind;

  /// The label shown in menus, such as "中文（简体） · zh-Hans".
  String get label => switch (kind) {
        SubtitleKind.uploaded => languageName(language, name),
        SubtitleKind.automatic => tr('{0}（自动生成）', [languageName(language, name)]),
        SubtitleKind.translated => tr('{0}（自动翻译）', [languageName(language, name)]),
      };

  /// yt-dlp's `subtitles` and `automatic_captions` maps. Automatic
  /// captions in the video's own language (yt-dlp's "-orig" entries, or
  /// those named "(Original)") come before the machine translations.
  static List<SubtitleOption> listFrom(Object? uploaded, Object? automatic) {
    List<SubtitleOption> read(Object? raw, bool auto) {
      if (raw is! Map) return const [];
      return [
        for (final MapEntry(:key, :value) in raw.entries)
          if (key != 'live_chat' && value is List)
            if (_vtt(value) case (final url, final name))
              SubtitleOption(
                language: '$key'.replaceFirst(RegExp(r'-orig$'), ''),
                name: name,
                url: url,
                kind: !auto
                    ? SubtitleKind.uploaded
                    : '$key'.endsWith('-orig') || name.contains('(Original)') || name.contains('原始')
                        ? SubtitleKind.automatic
                        : SubtitleKind.translated,
              ),
      ];
    }

    final auto = read(automatic, true);
    final original = auto.where((s) => s.kind == SubtitleKind.automatic).toList();
    // yt-dlp lists the original language twice: as "xx-orig" and as "xx".
    final originalLanguages = {for (final s in original) s.language};
    return [
      ...read(uploaded, false),
      ...{for (final s in original) s.language: s}.values,
      ...auto.where((s) => s.kind == SubtitleKind.translated && !originalLanguages.contains(s.language)),
    ];
  }

  static (String, String)? _vtt(List formats) {
    final maps = formats.whereType<Map>().where((f) => '${f['url'] ?? ''}'.startsWith('https://')).toList();
    final pick = maps.where((f) => f['ext'] == 'vtt').firstOrNull ?? maps.where((f) => f['ext'] == 'srt' || f['ext'] == 'ass').firstOrNull;
    return pick == null ? null : ('${pick['url']}', '${pick['name'] ?? ''}');
  }

  static final _names = {
    'zh-Hans': tr('中文（简体）'), 'zh-CN': tr('中文（中国）'), 'zh-Hant': tr('中文（繁體）'), 'zh-TW': tr('中文（台灣）'), 'zh-HK': tr('中文（香港）'), 'zh': tr('中文'),
    'en': tr('英语'), 'en-US': tr('英语（美国）'), 'en-GB': tr('英语（英国）'), 'ja': tr('日语'), 'ko': tr('韩语'), 'fr': tr('法语'), 'de': tr('德语'), 'es': tr('西班牙语'),
    'pt': tr('葡萄牙语'), 'pt-BR': tr('葡萄牙语（巴西）'), 'ru': tr('俄语'), 'it': tr('意大利语'), 'vi': tr('越南语'), 'th': tr('泰语'), 'id': tr('印尼语'), 'ms': tr('马来语'),
    'ar': tr('阿拉伯语'), 'hi': tr('印地语'), 'tr': tr('土耳其语'), 'nl': tr('荷兰语'), 'pl': tr('波兰语'), 'uk': tr('乌克兰语'), 'fil': tr('菲律宾语'),
  };

  /// A Chinese name for [code], else YouTube's own [name], else the code.
  static String languageName(String code, [String name = '']) {
    final known = _names[code];
    if (known != null) return known;
    final cleaned = name.replaceAll(RegExp(r'\s*\((Original|原始)\)'), '').trim();
    return cleaned.isEmpty ? code : '$cleaned · $code';
  }
}

enum SubtitleKind { uploaded, automatic, translated }

String formatBytes(int bytes) {
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}
