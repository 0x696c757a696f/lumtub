import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../app/app_controller.dart';
import '../church_wording.dart';
import '../l10n/l10n.dart';
import '../language_guess.dart';
import '../live_chat.dart';
import '../live_chat_composer.dart';
import '../translation.dart';
import '../translation_services.dart' show FallbackTranslator;
import 'app_icons.dart';
import 'common.dart';
import 'emoji_picker.dart';
import 'theme.dart';
import 'translatable.dart';

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
/// language show their translation, as 翻译布局 says.
class ImmersiveTranslationSwitch extends StatelessWidget {
  const ImmersiveTranslationSwitch({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
        valueListenable: FallbackTranslator.refusing,
        builder: (context, refusing, child) => _chip(context, standInNotice(controller)),
      );

  /// The chip, marked while another service stands in for the chosen one.
  Widget _chip(BuildContext context, String? standIn) {
    final on = controller.preferences.immersiveTranslation;
    return FilterChip(
      avatar: Icon(standIn != null && on ? AppIcons.warningCircle : AppIcons.translate, size: 16, color: chipForeground(context, on)),
      label: Text(tr('Immersive translation')),
      tooltip: standIn != null && on ? standIn : tr('Show translations in other languages automatically, as Translation layout says'),
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

/// Each message's translation, with the [AppController.translationSetup]
/// it was made under; made again under another.
final _translations = Expando<(String, Future<String?>)>();
final _askedTranslations = Expando<(String, Future<String?>)>();

Future<String?> _madeUnder(Expando<(String, Future<String?>)> made, LiveChatMessage message, String setup, Future<String?> Function() make) {
  final kept = made[message];
  if (kept != null && kept.$1 == setup) return kept.$2;
  final future = make();
  made[message] = (setup, future);
  return future;
}
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
            PositionedDirectional(
              top: 0,
              end: 0,
              child: ValueListenableBuilder(
                valueListenable: asked,
                builder: (context, on, _) => IconButton(
                  tooltip: on ? tr('Show original') : tr('Translation'),
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
  const ChatMessageTranslation({super.key, required this.controller, required this.message, required this.original});
  final AppController controller;
  final LiveChatMessage message;
  /// The message as written, shown with its translation as 翻译布局 says.
  final Widget original;

  /// Asked by hand, anything not already in the chosen language is
  /// translated; 沉浸式翻译 also leaves alone the languages listed as
  /// never translated.
  Future<String?> _translate({required bool asked}) async {
    final language = asked ? controller.preferences.translateTarget : controller.preferences.immersiveTarget;
    final known = asked ? {language} : readLanguages(controller);
    bool done(String line) => known.any((k) => readsAs(line, k, chineseAsOne: !asked && controller.preferences.chineseAsOne)) || !RegExp(r'\p{L}{2,}', unicode: true).hasMatch(line);
    // Channel emoji are written as :name: and are not words to translate.
    final text = message.emojis.keys.fold(message.text, (text, shortcut) => text.replaceAll(shortcut, ' ')).trim();
    if (text.split('\n').every(done)) return null;
    try {
      final result = await translateForeignLines(controller.textTranslator, text, language, done);
      return result.trim() == text ? null : ChurchWording.apply(result, language, rite: controller.playingRite, original: text);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([chatTranslation, chatMessageAsked(message), controller.translationSetup]),
        builder: (context, _) {
          if (!chatTranslation.value && !chatMessageAsked(message).value) return original;
          return FutureBuilder(
            future: chatMessageAsked(message).value
                ? _madeUnder(_askedTranslations, message, controller.translationSetup.value, () => _translate(asked: true))
                : _madeUnder(_translations, message, controller.translationSetup.value, () => _translate(asked: false)),
            builder: (context, snapshot) {
              final text = snapshot.data;
              if (text == null) return original;
              final prefs = controller.preferences;
              final translated = SelectionArea(child: Text(text));
              // 翻译布局, as for comments and posts.
              if (!prefs.bilingualTranslation) return Padding(padding: const EdgeInsets.only(top: Space.xs), child: translated);
              final under = Padding(padding: const EdgeInsets.only(top: Space.xs), child: TranslationView(style: prefs.translationStyle, child: translated));
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: prefs.translationFirst ? [under, original] : [original, under]);
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
      box = ChatBoxClosed(tr("Couldn't open the chat box"));
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
      _error = tr("Couldn't send. Check the network or proxy");
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
          IconButton(tooltip: tr('Retry'), icon: Icon(AppIcons.arrowClockwise, size: 18), onPressed: _open),
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
              decoration: InputDecoration(hintText: tr('Say something in the chat')),
            ),
          ),
          EmojiButton(field: _text, focus: _focus, channel: box is ChatBoxOpen ? box.emojis : const []),
          IconButton(
            tooltip: tr('Super Chat: pay and send on YouTube in your browser'),
            icon: Icon(AppIcons.handHeart, size: 18),
            // The pop-out chat, where YouTube keeps the Super Chat button.
            onPressed: () => unawaited(openExternal('https://www.youtube.com/live_chat?is_popout=1&v=${widget.videoId}')),
          ),
          IconButton.filledTonal(
            tooltip: tr('Send'),
            onPressed: _sending ? null : () => unawaited(_send()),
            icon: _sending ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)) : Icon(AppIcons.paperPlaneRight, size: 18),
          ),
        ]),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: Space.xs), child: Text(_error!, style: context.text.bodySmall?.copyWith(color: context.colors.error))),
      ]),
    );
  }
}
