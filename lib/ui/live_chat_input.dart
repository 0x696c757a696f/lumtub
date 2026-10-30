import 'dart:async';

import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../l10n/l10n.dart';
import '../language_guess.dart';
import '../live_chat.dart';
import '../live_chat_composer.dart';
import '../translation.dart';
import 'app_icons.dart';
import 'theme.dart';

/// 沉浸式翻译 for the live chat rows, which are kept between rebuilds and
/// so listen to this rather than the preferences; [syncChatTranslation]
/// follows the preference.
final chatTranslation = ValueNotifier(false);

void syncChatTranslation(AppController controller) {
  final on = controller.preferences.immersiveTranslation;
  if (chatTranslation.value == on) return;
  WidgetsBinding.instance.addPostFrameCallback((_) => chatTranslation.value = controller.preferences.immersiveTranslation);
}

/// The 沉浸式翻译 switch: comments, posts and the live chat in another
/// language show their translation under them.
class ImmersiveTranslationSwitch extends StatelessWidget {
  const ImmersiveTranslationSwitch({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final on = controller.preferences.immersiveTranslation;
    return FilterChip(
      avatar: Icon(AppIcons.translate, size: 16),
      label: Text(tr('沉浸式翻译')),
      tooltip: tr('外语内容自动在下方显示译文'),
      selected: on,
      showCheckmark: false,
      visualDensity: VisualDensity.compact,
      onSelected: (value) {
        chatTranslation.value = value;
        unawaited(controller.savePreferences(controller.preferences.copyWith(immersiveTranslation: value)));
      },
    );
  }
}

final _translations = Expando<Future<String?>>();
final _asked = Expando<ValueNotifier<bool>>();

/// Whether [message] was asked to be translated by hand.
ValueNotifier<bool> chatMessageAsked(LiveChatMessage message) => _asked[message] ??= ValueNotifier(false);

/// A small 翻译 button that shows while the pointer is over [child]; a
/// long press does the same on touch.
class ChatMessageTranslateButton extends StatefulWidget {
  const ChatMessageTranslateButton({super.key, required this.message, required this.child});
  final LiveChatMessage message;
  final Widget child;

  @override
  State<ChatMessageTranslateButton> createState() => _ChatMessageTranslateButtonState();
}

class _ChatMessageTranslateButtonState extends State<ChatMessageTranslateButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final asked = chatMessageAsked(widget.message);
    void toggle() => asked.value = !asked.value;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onLongPress: toggle,
        child: Stack(children: [
          widget.child,
          if (_hover && widget.message.text.trim().isNotEmpty)
            Positioned(
              top: 0,
              right: 0,
              child: ValueListenableBuilder(
                valueListenable: asked,
                builder: (context, on, _) => IconButton(
                  tooltip: on ? tr('显示原文') : tr('翻译'),
                  visualDensity: VisualDensity.compact,
                  iconSize: 16,
                  style: IconButton.styleFrom(backgroundColor: context.colors.surfaceContainerHigh),
                  icon: Icon(AppIcons.translate),
                  onPressed: toggle,
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

/// The translation of [message] while [chatTranslation] is on or it was
/// asked for by hand; nothing
/// when it is off or the message is already in the chosen language. Each
/// message is translated once, when it is first shown.
class ChatMessageTranslation extends StatelessWidget {
  const ChatMessageTranslation({super.key, required this.controller, required this.message});
  final AppController controller;
  final LiveChatMessage message;

  Future<String?> _translate() async {
    final language = controller.preferences.translateTarget;
    bool done(String line) => looksLike(line, language) || !RegExp(r'\p{L}{2,}', unicode: true).hasMatch(line);
    if (message.text.trim().isEmpty || done(message.text)) return null;
    try {
      final result = await translateForeignLines(controller.translator, message.text, language, done);
      return result.trim() == message.text.trim() ? null : result;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([chatTranslation, chatMessageAsked(message)]),
        builder: (context, _) {
          if (!chatTranslation.value && !chatMessageAsked(message).value) return const SizedBox.shrink();
          return FutureBuilder(
            future: _translations[message] ??= _translate(),
            builder: (context, snapshot) {
              final text = snapshot.data;
              if (text == null) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: Space.xs),
                child: SelectionArea(child: Text(text, style: TextStyle(color: context.colors.onSurfaceVariant))),
              );
            },
          );
        },
      );
}

/// The box for writing in the live chat of [videoId], as the cookie
/// sign-in; it says why when this account cannot write there.
class LiveChatInput extends StatefulWidget {
  const LiveChatInput({super.key, required this.controller, required this.videoId});
  final AppController controller;
  final String videoId;

  @override
  State<LiveChatInput> createState() => _LiveChatInputState();
}

class _LiveChatInputState extends State<LiveChatInput> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  ChatBox? _box;
  bool _sending = false;
  String? _error;
  int _opening = 0;

  @override
  void initState() {
    super.initState();
    _open();
  }

  @override
  void didUpdateWidget(LiveChatInput old) {
    super.didUpdateWidget(old);
    if (old.videoId != widget.videoId) _open();
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    final serial = ++_opening;
    setState(() {
      _box = null;
      _error = null;
    });
    ChatBox box;
    try {
      box = await LiveChatComposer(widget.controller.webSignIn).open(widget.videoId);
    } catch (_) {
      box = ChatBoxClosed(tr('无法打开聊天的输入框'));
    }
    if (mounted && serial == _opening) setState(() => _box = box);
  }

  Future<void> _send() async {
    final box = _box;
    final text = _text.text.trim();
    if (box is! ChatBoxOpen || text.isEmpty || _sending) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await LiveChatComposer(widget.controller.webSignIn).send(box, text);
      _text.clear();
    } on StateError catch (e) {
      _error = e.message;
    } catch (_) {
      _error = tr('发送失败，请检查网络或代理');
    }
    if (!mounted) return;
    setState(() => _sending = false);
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final box = _box;
    if (box == null) return const SizedBox(height: Space.huge, child: Center(child: SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))));
    if (box is ChatBoxClosed) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.s),
        child: Row(children: [
          Icon(AppIcons.lockSimple, size: 16, color: context.colors.outline),
          const SizedBox(width: Space.s),
          Expanded(child: Text(box.reason, style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant))),
          IconButton(tooltip: tr('重试'), icon: Icon(AppIcons.arrowClockwise, size: 18), onPressed: _open),
        ]),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.s),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Expanded(
            child: TextField(
              controller: _text,
              focusNode: _focus,
              enabled: !_sending,
              maxLength: 200,
              buildCounter: (context, {required currentLength, required isFocused, required maxLength}) => null,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => unawaited(_send()),
              decoration: InputDecoration(hintText: tr('在聊天里说点什么')),
            ),
          ),
          const SizedBox(width: Space.s),
          IconButton.filledTonal(
            tooltip: tr('发送'),
            onPressed: _sending ? null : () => unawaited(_send()),
            icon: _sending ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)) : Icon(AppIcons.paperPlaneRight, size: 18),
          ),
        ]),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: Space.xs), child: Text(_error!, style: context.text.bodySmall?.copyWith(color: context.colors.error))),
      ]),
    );
  }
}
