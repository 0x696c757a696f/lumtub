import 'dart:convert';

import 'package:http/http.dart' as http;

import 'l10n/l10n.dart';
import 'models.dart';

/// What a pasted youtube.com link other than a video's leads to.
sealed class YoutubeLink {
  const YoutubeLink();

  /// The channel, playlist or nothing [input] links to; videos are
  /// `AppController.parseYoutubeId`'s.
  static YoutubeLink? parse(String input) {
    final text = input.trim();
    final url = Uri.tryParse(RegExp(r'^[a-z]+://', caseSensitive: false).hasMatch(text) ? text : 'https://$text');
    if (url == null || url.scheme != 'https') return null;
    if (!const {'youtube.com', 'www.youtube.com', 'm.youtube.com', 'music.youtube.com'}.contains(url.host)) return null;
    final path = url.pathSegments.where((part) => part.isNotEmpty).toList();
    if (path.isEmpty) return null;
    if (path.first == 'playlist') {
      final id = url.queryParameters['list'] ?? '';
      return PlaylistResult.isValidId(id) ? PlaylistLink(id) : null;
    }
    if (path.first == 'channel' && path.length >= 2 && ChannelRef.isValidId(path[1])) return ChannelLink(path[1]);
    if (path.first.startsWith('@') && RegExp(r'^@[^\s/?#&]{1,100}$').hasMatch(path.first)) return HandleLink(path.first);
    return null;
  }
}

/// A `/channel/UC…` link.
class ChannelLink extends YoutubeLink {
  const ChannelLink(this.id);
  final String id;
}

/// A `/@name` link.
class HandleLink extends YoutubeLink {
  const HandleLink(this.handle);
  final String handle;
}

/// A `/playlist?list=…` link.
class PlaylistLink extends YoutubeLink {
  const PlaylistLink(this.id);
  final String id;
}

/// The title and owner of playlist [id] from YouTube's oEmbed answer, or
/// null.
Future<PlaylistResult?> linkPlaylist(http.Client client, String id, {Duration timeout = const Duration(seconds: 4)}) async {
  try {
    final address = Uri.https('www.youtube.com', '/oembed', {'url': 'https://www.youtube.com/playlist?list=$id', 'format': 'json'});
    final reply = await client.get(address).timeout(timeout);
    if (reply.statusCode != 200) return null;
    final answer = jsonDecode(utf8.decode(reply.bodyBytes));
    if (answer is! Map || answer['title'] is! String) return null;
    return PlaylistResult(id: id, title: (answer['title'] as String).trim(), channel: answer['author_name'] is String ? (answer['author_name'] as String).trim() : '');
  } catch (_) {
    return null;
  }
}

/// What a pasted youtube.com or youtu.be link to [id] is, before anything
/// else is known: a card that names the video by its id.
VideoItem linkPlaceholder(String id) => VideoItem(id: id, title: tr('YouTube video · {0}', [id]), channel: 'YouTube', url: 'https://www.youtube.com/watch?v=$id');

/// Whether [item] is still only [linkPlaceholder]: no channel known and
/// the id for a title.
bool isLinkPlaceholder(VideoItem item) => item.channelId == null && item.channel == 'YouTube' && item.title.contains(item.id);

/// The title and channel name of video [id] from YouTube's oEmbed answer,
/// which comes back in well under a second; null when YouTube does not
/// answer (private or removed video, no network).
Future<VideoItem?> linkVideo(http.Client client, String id, {Duration timeout = const Duration(seconds: 4)}) async {
  try {
    final address = Uri.https('www.youtube.com', '/oembed', {'url': 'https://www.youtube.com/watch?v=$id', 'format': 'json'});
    final reply = await client.get(address).timeout(timeout);
    if (reply.statusCode != 200) return null;
    return linkVideoOf(id, jsonDecode(utf8.decode(reply.bodyBytes)));
  } catch (_) {
    return null;
  }
}

/// [linkVideo]'s card from the decoded oEmbed [answer].
VideoItem? linkVideoOf(String id, Object? answer) {
  if (answer is! Map) return null;
  final title = answer['title'];
  final channel = answer['author_name'];
  if (title is! String || title.trim().isEmpty) return null;
  return VideoItem(
    id: id,
    title: title.trim(),
    channel: channel is String ? channel.trim() : '',
    url: 'https://www.youtube.com/watch?v=$id',
    width: answer['width'] is int ? answer['width'] as int : null,
    height: answer['height'] is int ? answer['height'] as int : null,
  );
}

/// [item] with what [details] know and it does not: title and channel
/// when [item] is a [linkPlaceholder] or has none, the channel's id, views,
/// upload day and [length].
VideoItem filledFromDetails(VideoItem item, VideoDetails details, {int? length}) {
  final placeholder = isLinkPlaceholder(item);
  return VideoItem(
    id: item.id,
    title: (placeholder || item.title.trim().isEmpty) && details.title.isNotEmpty ? details.title : item.title,
    channel: (placeholder || item.channel.trim().isEmpty || item.channel == 'YouTube') && details.channel.isNotEmpty ? details.channel : item.channel,
    duration: item.duration ?? (item.isLive ? null : length),
    url: item.url,
    viewCount: item.viewCount ?? (item.isLive ? null : details.viewCount),
    watching: item.watching,
    channelId: item.channelId ?? details.channelId,
    published: item.published ?? (item.age == null ? details.uploadDate : null),
    liveStatus: item.liveStatus,
    scheduledStart: item.scheduledStart ?? details.scheduledStart,
    width: item.width,
    height: item.height,
    description: item.description ?? (details.description.isEmpty ? null : details.description.substring(0, details.description.length.clamp(0, 300))),
    isShortListing: item.isShortListing,
    membersOnly: item.membersOnly,
    age: item.age,
  );
}

/// Whether [filled] says more than [item]: worth showing and saving.
bool saysMore(VideoItem item, VideoItem filled) =>
    filled.title != item.title ||
    filled.channel != item.channel ||
    filled.channelId != item.channelId ||
    filled.viewCount != item.viewCount ||
    filled.published != item.published ||
    filled.duration != item.duration;
