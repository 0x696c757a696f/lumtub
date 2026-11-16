import 'dart:convert';

import 'package:http/http.dart' as http;

import 'l10n/l10n.dart';
import 'models.dart';

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
