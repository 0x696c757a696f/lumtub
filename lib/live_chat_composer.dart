import 'dart:convert';
import 'dart:ffi';
import 'dart:math';

import 'package:ffi/ffi.dart';

import 'app_log.dart';
import 'l10n/l10n.dart';
import 'native_core.dart';
import 'youtube_web_sign_in.dart';

/// Whether this account can write in a live chat, and why not.
sealed class ChatBox {
  const ChatBox();
}

class ChatBoxOpen extends ChatBox {
  const ChatBoxOpen(this.params, {this.emojis = const []});
  final String params;
  /// The channel's own emoji in this chat.
  final List<ChannelEmoji> emojis;
}

/// A channel emoji of a live chat: typed as [shortcut] (`:_wave:`), sent as
/// [id]; [locked] ones are for the channel's members.
class ChannelEmoji {
  const ChannelEmoji({required this.id, required this.shortcut, required this.url, this.locked = false});
  final String id;
  final String shortcut;
  final String url;
  final bool locked;

  static ChannelEmoji? fromJson(Object? raw) {
    if (raw is! Map || raw['id'] is! String || raw['shortcut'] is! String || raw['url'] is! String) return null;
    return ChannelEmoji(id: raw['id'] as String, shortcut: raw['shortcut'] as String, url: raw['url'] as String, locked: raw['locked'] == true);
  }
}

class ChatBoxClosed extends ChatBox {
  const ChatBoxClosed(this.reason);
  final String reason;
}

/// Writing in a live chat as the cookie sign-in: the website's chat box,
/// found through the watch page and the chat itself, then
/// `live_chat/send_message`. The answers are read by the Rust core
/// (native/lumtub_core/src/live_chat.rs).
class LiveChatComposer {
  LiveChatComposer(this.web);
  final YoutubeWebSignIn? web;

  static Pointer<Utf8> Function(Pointer<Uint8>, int)? _composer;
  static Pointer<Utf8> Function(Pointer<Uint8>, int)? _sendBody;
  static bool _tried = false;

  static void _bind() {
    if (_tried) return;
    _tried = true;
    final library = NativeCore.instance?.library;
    if (library == null) return;
    try {
      _composer = library.lookupFunction<Pointer<Utf8> Function(Pointer<Uint8>, Size), Pointer<Utf8> Function(Pointer<Uint8>, int)>('lumtub_live_chat_composer');
      _sendBody = library.lookupFunction<Pointer<Utf8> Function(Pointer<Uint8>, Size), Pointer<Utf8> Function(Pointer<Uint8>, int)>('lumtub_live_chat_send_body');
    } catch (_) {
      _composer = _sendBody = null;
    }
  }

  static Map<String, Object?> _read(List<int> body) {
    _bind();
    final core = NativeCore.instance;
    final call = _composer;
    if (core == null || call == null) return const {};
    return (jsonDecode(core.take(core.withBytes(body, call)) ?? 'null') as Map?)?.cast<String, Object?>() ?? const {};
  }

  /// The chat box of live video [videoId].
  Future<ChatBox> open(String videoId) async {
    final web = this.web;
    if (web == null || !web.signedIn) return ChatBoxClosed(tr('Sign in with your browser (cookies) to write in the chat'));
    _bind();
    if (_composer == null) return ChatBoxClosed(tr("The installation is incomplete, so the chat can't be written in"));
    final watch = await web.post('next', {'videoId': videoId});
    if (watch == null) return ChatBoxClosed(tr('Sign in with your browser (cookies) to write in the chat'));
    final continuation = watch.status == 200 ? _read(watch.body)['continuation'] as String? : null;
    if (continuation == null) {
      logWarn('No live chat box for $videoId (watch page answered ${watch.status})');
      return ChatBoxClosed(tr("This live chat can't be written in"));
    }
    final chat = await web.post('live_chat/get_live_chat', {'continuation': continuation});
    if (chat == null || chat.status != 200) {
      logWarn('The live chat of $videoId answered ${chat?.status}');
      return ChatBoxClosed(tr("Couldn't open the chat box"));
    }
    final box = _read(chat.body);
    if (box['params'] case final String params) {
      final emojis = (box['emojis'] as List? ?? const []).map(ChannelEmoji.fromJson).whereType<ChannelEmoji>().toList();
      return ChatBoxOpen(params, emojis: emojis);
    }
    return ChatBoxClosed(box['restricted'] as String? ?? tr("This account can't write in this live chat"));
  }

  /// Sends [text] through [box]; throws a message for the user when
  /// YouTube does not take it.
  Future<void> send(ChatBoxOpen box, String text) async {
    final web = this.web;
    final core = NativeCore.instance;
    final made = _sendBody;
    if (web == null || core == null || made == null) throw StateError(tr('Sign in with your browser (cookies) to write in the chat'));
    final id = List.generate(16, (_) => Random.secure().nextInt(36).toRadixString(36)).join();
    final request = core.take(core.withText(jsonEncode({
      'params': box.params,
      'text': text,
      'clientMessageId': id,
      'emojis': {for (final e in box.emojis) if (!e.locked) e.shortcut: e.id},
    }), made));
    if (request == null) return;
    final answer = await web.post('live_chat/send_message', (jsonDecode(request) as Map).cast<String, Object?>(), ask: true);
    if (answer == null) throw StateError(tr('Sign in with your browser (cookies) to write in the chat'));
    if (answer.status != 200) {
      logWarn('YouTube answered ${answer.status} to a live chat message');
      throw StateError(tr("YouTube didn't accept the message ({0})", [answer.status]));
    }
  }
}
