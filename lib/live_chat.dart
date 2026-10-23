import 'dart:convert';

/// A read-only item from yt-dlp's `live_chat` JSON subtitle stream.
///
/// yt-dlp writes one JSON action per line. Replay actions include an offset
/// into the video; current live-chat actions do not.
enum LiveChatKind { message, paidMessage, paidSticker, membership, system }

class LiveChatMessage {
  const LiveChatMessage({
    required this.id,
    required this.kind,
    required this.text,
    this.offset,
    this.timestampUsec,
    this.author = '',
    this.authorChannelId,
    this.authorAvatar,
    this.amount,
    this.stickerUrl,
  });

  final String id;
  final LiveChatKind kind;
  final String text;
  /// Position in a recorded live stream, absent for an active live chat.
  final Duration? offset;
  final int? timestampUsec;
  final String author;
  final String? authorChannelId;
  final String? authorAvatar;
  /// YouTube's already-formatted Super Chat or Super Sticker amount.
  final String? amount;
  /// The Super Sticker image, when this is a paid sticker.
  final String? stickerUrl;

  /// Parses one yt-dlp `live_chat` line. Status actions without a chat item
  /// and unknown renderer types are left out.
  static List<LiveChatMessage> parseLine(String line) {
    final raw = jsonDecode(line);
    if (raw is! Map) return const [];
    final replay = raw['replayChatItemAction'];
    final action = replay is Map ? replay : raw;
    final offsetMs = int.tryParse('${action['videoOffsetTimeMsec'] ?? ''}');
    final offset = offsetMs == null ? null : Duration(milliseconds: offsetMs);
    final actions = action['actions'];
    if (actions is! List) return const [];
    return [
      for (final entry in actions.whereType<Map>())
        if (entry['addChatItemAction'] case final Map add)
          if (add['item'] case final Map item)
            if (_fromItem(item, offset: offset) case final message?) message,
    ];
  }

  /// Parses a complete `.live_chat.json` file written by yt-dlp.
  static List<LiveChatMessage> parseLines(String contents) => [
        for (final line in const LineSplitter().convert(contents))
          if (line.trim().isNotEmpty) ...parseLine(line),
      ];

  static LiveChatMessage? _fromItem(Map item, {required Duration? offset}) {
    final found = <(LiveChatKind, Map)>[
      if (item['liveChatTextMessageRenderer'] case final Map renderer) (LiveChatKind.message, renderer),
      if (item['liveChatPaidMessageRenderer'] case final Map renderer) (LiveChatKind.paidMessage, renderer),
      if (item['liveChatPaidStickerRenderer'] case final Map renderer) (LiveChatKind.paidSticker, renderer),
      if (item['liveChatMembershipItemRenderer'] case final Map renderer) (LiveChatKind.membership, renderer),
      if (item['liveChatViewerEngagementMessageRenderer'] case final Map renderer) (LiveChatKind.system, renderer),
    ];
    if (found.isEmpty) return null;
    final (kind, renderer) = found.first;
    final text = _text(renderer['message']).isNotEmpty
        ? _text(renderer['message'])
        : _text(renderer['headerSubtext']).isNotEmpty
            ? _text(renderer['headerSubtext'])
            : _text(renderer['headerPrimaryText']);
    final id = '${renderer['id'] ?? ''}';
    if (id.isEmpty) return null;
    final authorPhoto = renderer['authorPhoto'];
    String? avatar;
    if (authorPhoto is Map && authorPhoto['thumbnails'] is List) {
      for (final thumbnail in authorPhoto['thumbnails'] as List) {
        if (thumbnail is Map && thumbnail['url'] is String) avatar = thumbnail['url'] as String;
      }
    }
    final amount = _text(renderer['purchaseAmountText']);
    String? stickerUrl;
    if (renderer['sticker'] case final Map sticker) {
      final thumbnails = sticker['thumbnails'];
      if (thumbnails is List) {
        for (final thumbnail in thumbnails) {
          if (thumbnail is Map && thumbnail['url'] is String) stickerUrl = thumbnail['url'] as String;
        }
      }
    }
    return LiveChatMessage(
      id: id,
      kind: kind,
      text: text,
      offset: offset,
      timestampUsec: int.tryParse('${renderer['timestampUsec'] ?? ''}'),
      author: _text(renderer['authorName']),
      authorChannelId: renderer['authorExternalChannelId']?.toString(),
      authorAvatar: avatar,
      amount: amount.isEmpty ? null : amount,
      stickerUrl: stickerUrl,
    );
  }

  static String _text(Object? raw) {
    if (raw is! Map) return '';
    final simple = raw['simpleText'];
    if (simple is String) return simple;
    final runs = raw['runs'];
    if (runs is! List) return '';
    return runs.whereType<Map>().map((run) {
      final text = run['text'];
      if (text is String) return text;
      final emoji = run['emoji'];
      if (emoji is Map) {
        final shortcuts = emoji['shortcuts'];
        if (shortcuts is List && shortcuts.isNotEmpty) return '${shortcuts.first}';
        final accessibility = emoji['accessibility'];
        if (accessibility is Map) {
          final data = accessibility['accessibilityData'];
          if (data is Map) return '${data['label'] ?? ''}';
        }
      }
      return '';
    }).join();
  }
}
