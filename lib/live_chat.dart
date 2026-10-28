import 'dart:convert';

import 'native_core.dart';

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
    this.emojis = const {},
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
  /// Custom emoji in [text]: shortcut to picture address.
  final Map<String, String> emojis;

  /// Parses one yt-dlp `live_chat` line. Status actions without a chat item
  /// and unknown renderer types are left out.
  static List<LiveChatMessage> parseLine(String line) => _read(line);

  /// Parses a complete `.live_chat.json` file written by yt-dlp.
  static List<LiveChatMessage> parseLines(String contents) => _read(contents);

  /// The chat items of [lines], read by the native core; none without it.
  static List<LiveChatMessage> _read(String lines) {
    final core = NativeCore.instance;
    final list = core == null ? null : jsonDecode(core.take(core.withText(lines, core.liveChat)) ?? 'null');
    if (list is! List) return const [];
    return [
      for (final m in list.cast<Map<String, dynamic>>())
        LiveChatMessage(
          id: m['id'] as String,
          kind: LiveChatKind.values.byName(m['kind'] as String),
          text: m['text'] as String,
          offset: m['offsetMs'] == null ? null : Duration(milliseconds: (m['offsetMs'] as num).toInt()),
          timestampUsec: (m['timestampUsec'] as num?)?.toInt(),
          author: m['author'] as String,
          authorChannelId: m['authorChannelId'] as String?,
          authorAvatar: m['authorAvatar'] as String?,
          amount: m['amount'] as String?,
          stickerUrl: m['stickerUrl'] as String?,
          emojis: (m['emojis'] as Map<String, dynamic>?)?.cast<String, String>() ?? const {},
        ),
    ];
  }
}
