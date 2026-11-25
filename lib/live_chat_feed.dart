import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:http/http.dart' as http;

import 'app_log.dart';
import 'l10n/l10n.dart';
import 'live_chat.dart';
import 'native_core.dart';
import 'youtube_web.dart';

/// What one answer of YouTube's chat brought, as the native core reads it
/// (native/lumtub_core/src/live_chat.rs, `answer`).
class LiveChatBatch {
  const LiveChatBatch({
    this.messages = const [],
    this.removed = const {},
    this.removedAuthors = const {},
    this.restricted,
    this.view,
  });

  final List<LiveChatMessage> messages;
  /// Messages the channel's moderators took down.
  final Set<String> removed;
  /// Channels whose messages were all taken down.
  final Set<String> removedAuthors;
  /// Who may write, when not everyone may.
  final String? restricted;
  /// The view these messages come from; null when the chat offers only one.
  final ChatView? view;
}

class _Answer {
  const _Answer({
    this.start,
    this.visitor,
    this.replay = false,
    this.next,
    this.timeoutMs,
    this.views = const [],
    this.batch = const LiveChatBatch(),
  });

  final String? start;
  final String? visitor;
  final bool replay;
  final String? next;
  final int? timeoutMs;
  /// Each view's continuation and whether it is the one answered with.
  final List<(String, bool)> views;
  final LiveChatBatch batch;

  static _Answer read(Map<String, dynamic> raw) {
    Set<String> ids(String key) => {for (final id in (raw[key] as List? ?? const [])) if (id is String) id};
    return _Answer(
      start: raw['start'] as String?,
      visitor: raw['visitor'] as String?,
      replay: raw['replay'] == true,
      next: raw['next'] as String?,
      timeoutMs: (raw['timeoutMs'] as num?)?.toInt(),
      views: [
        for (final view in (raw['views'] as List? ?? const []).cast<Map<String, dynamic>>()) (view['continuation'] as String, view['selected'] == true),
      ],
      batch: LiveChatBatch(
        messages: [for (final m in (raw['messages'] as List? ?? const []).cast<Map<String, dynamic>>()) LiveChatMessage.fromCore(m)],
        removed: ids('removed'),
        removedAuthors: ids('removedAuthors'),
        restricted: raw['restricted'] as String?,
      ),
    );
  }
}

/// The visitor id one chat is read with.
class _Session {
  String? visitor;
}

/// The chat closed for the video asked about: none, or none public.
class NoLiveChat implements Exception {
  const NoLiveChat();
  @override
  String toString() => 'no public chat';
}

/// Reads a live chat or a chat replay the way YouTube's website does, so
/// that Top chat or every message can be picked: `next` names the chat,
/// then `live_chat/get_live_chat` (or `get_live_chat_replay`) is followed
/// answer by answer. Signed out, like the rest of what is watched.
class LiveChatFeed {
  LiveChatFeed(this._client, {this.base = 'https://www.youtube.com'});

  final http.Client _client;
  /// Another server than YouTube, for tests.
  final String base;

  /// The most read from one answer; a busy chat's is under a megabyte.
  static const maxBytes = 8 << 20;
  /// Answers larger than this are read away from the UI isolate.
  static const _inBackground = 128 << 10;
  /// The most messages read from one replay, as from yt-dlp's file.
  static const maxReplayMessages = 200000;
  /// Waits between a live chat's requests, whatever YouTube asks.
  static const minWait = Duration(milliseconds: 1000);
  static const maxWait = Duration(seconds: 10);
  /// Tries of one request before the chat is given up.
  static const _tries = 5;

  static Pointer<Utf8> Function(Pointer<Uint8>, int)? _answer;
  static bool _bound = false;

  static Pointer<Utf8> Function(Pointer<Uint8>, int)? _bind() {
    if (_bound) return _answer;
    _bound = true;
    try {
      _answer = NativeCore.instance?.library.lookupFunction<Pointer<Utf8> Function(Pointer<Uint8>, Size), Pointer<Utf8> Function(Pointer<Uint8>, int)>('lumtub_live_chat_answer');
    } catch (_) {
      _answer = null;
    }
    return _answer;
  }

  /// Whether this build's core reads chat answers.
  static bool get available => _bind() != null;

  /// [body], an answer from YouTube, as the core reads it.
  static _Answer _parse(Uint8List body) {
    final core = NativeCore.instance;
    final call = _bind();
    if (core == null || call == null) return const _Answer();
    final raw = jsonDecode(core.take(core.withBytes(body, call)) ?? 'null');
    return raw is Map<String, dynamic> ? _Answer.read(raw) : const _Answer();
  }

  Future<_Answer> _post(_Session session, String endpoint, Map<String, Object?> body) async {
    final visitor = session.visitor;
    final request = http.Request('POST', Uri.parse('$base/youtubei/v1/$endpoint?prettyPrint=false'))
      ..headers.addAll(YoutubeWeb.apiHeaders(acceptLanguage: youtubeAcceptLanguage))
      ..headers.addAll({if (visitor != null) 'X-Goog-Visitor-Id': visitor})
      ..body = jsonEncode({
        'context': {
          'client': {
            'clientName': 'WEB',
            'clientVersion': YoutubeWeb.clientVersion,
            'hl': youtubeHl,
            if (visitor != null) 'visitorData': visitor,
          },
        },
        ...body,
      });
    final response = await _client.send(request).timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      await response.stream.drain<void>().catchError((_) {});
      throw http.ClientException('YouTube answered ${response.statusCode} to $endpoint');
    }
    if ((response.contentLength ?? 0) > maxBytes) throw http.ClientException('The answer to $endpoint is over ${maxBytes >> 20} MiB');
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response.stream.timeout(const Duration(seconds: 20))) {
      if (bytes.length + chunk.length > maxBytes) throw http.ClientException('The answer to $endpoint is over ${maxBytes >> 20} MiB');
      bytes.add(chunk);
    }
    final body0 = bytes.takeBytes();
    final answer = body0.length > _inBackground ? await Isolate.run(() => _parse(body0)) : _parse(body0);
    if (answer.visitor != null) session.visitor = answer.visitor;
    return answer;
  }

  /// [_post], tried again a few times, waiting longer each time.
  Future<_Answer> _postTrying(_Session session, String endpoint, Map<String, Object?> body, bool Function() stopped) async {
    for (var attempt = 1;; attempt++) {
      try {
        return await _post(session, endpoint, body);
      } catch (error) {
        if (attempt >= _tries || stopped()) rethrow;
        logDebug(() => 'Live chat: $endpoint failed ($error), try $attempt of $_tries');
        await Future<void>.delayed(Duration(seconds: 1 << attempt));
        if (stopped()) rethrow;
      }
    }
  }

  /// Follows the chat of [videoId]: a live stream's as it is written, a
  /// replay's from the start to the end. [view] picks the messages, when
  /// the chat offers both views. Errors before the first batch mean this
  /// way of reading failed; a chat that has none throws [NoLiveChat].
  Stream<LiveChatBatch> follow(String videoId, ChatView view) {
    var stopped = false;
    late final StreamController<LiveChatBatch> out;
    Future<void> run() async {
      try {
        if (!available) throw StateError(tr("The installation is incomplete, so the chat can't be read"));
        final session = _Session();
        final opened = await _post(session, 'next', {'videoId': videoId});
        final start = opened.start;
        if (start == null) throw const NoLiveChat();
        final replay = opened.replay;
        final endpoint = replay ? 'live_chat/get_live_chat_replay' : 'live_chat/get_live_chat';
        Map<String, Object?> ask(String continuation, int offset) => {
              'continuation': continuation,
              if (replay) 'currentPlayerState': {'playerOffsetMs': '${max(0, offset - 5000)}'},
            };
        if (stopped) return;
        var answer = await _post(session, endpoint, ask(start, 0));
        final restricted = answer.batch.restricted;
        final views = answer.views.isNotEmpty ? answer.views : opened.views;
        // Top chat first, every message second, as yt-dlp reads them too.
        final want = view == ChatView.top ? 0 : 1;
        ChatView? shown;
        if (views.length >= 2) {
          if (!views[want].$2) {
            if (stopped) return;
            answer = await _post(session, endpoint, ask(views[want].$1, 0));
          }
          shown = view;
        }
        var count = 0;
        var offset = 0;
        String? last;
        var repeats = 0;
        while (!stopped) {
          final batch = answer.batch;
          count += batch.messages.length;
          for (final message in batch.messages) {
            final at = message.offset?.inMilliseconds;
            if (at != null && at > offset) offset = at;
          }
          out.add(LiveChatBatch(
            messages: batch.messages,
            removed: batch.removed,
            removedAuthors: batch.removedAuthors,
            restricted: batch.restricted ?? restricted,
            view: shown,
          ));
          final next = answer.next;
          if (next == null || (replay && count >= maxReplayMessages)) break;
          // The same request answered without anything new, again and
          // again: the chat is not moving on.
          repeats = next == last && batch.messages.isEmpty ? repeats + 1 : 0;
          if (repeats >= 3) break;
          last = next;
          if (!replay) {
            final wait = Duration(milliseconds: answer.timeoutMs ?? 5000);
            await Future<void>.delayed(wait < minWait ? minWait : (wait > maxWait ? maxWait : wait));
            if (stopped) break;
          }
          answer = await _postTrying(session, endpoint, ask(next, offset), () => stopped);
        }
      } catch (error, stack) {
        if (!stopped) out.addError(error, stack);
      } finally {
        if (!out.isClosed) await out.close();
      }
    }

    out = StreamController<LiveChatBatch>(
      onListen: () => unawaited(run()),
      onCancel: () => stopped = true,
    );
    return out.stream;
  }
}
