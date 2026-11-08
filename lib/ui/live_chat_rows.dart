import 'dart:async';

import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../l10n/l10n.dart';
import '../live_chat.dart';
import '../models.dart';
import 'app_icons.dart';
import 'emoji_text.dart';
import 'live_chat_input.dart';
import 'pages/channel_page.dart';
import 'theme.dart';

/// Whether Super Chats show in their amount's colour, followed by the rows
/// kept between rebuilds; [syncSuperChatHighlights] follows the preference.
final superChatHighlights = ValueNotifier(true);

void syncSuperChatHighlights(AppController controller) {
  final on = controller.preferences.superChatHighlights;
  if (superChatHighlights.value == on) return;
  WidgetsBinding.instance.addPostFrameCallback((_) => superChatHighlights.value = controller.preferences.superChatHighlights);
}

/// Text that reads on [background]: black on light tiers, white on dark.
Color _onTier(Color background) => background.computeLuminance() > 0.4 ? Colors.black : Colors.white;

/// Opens the channel of [message]'s author, when the chat names it.
VoidCallback? _openAuthor(AppController controller, LiveChatMessage message) {
  final id = message.authorChannelId;
  if (id == null || !ChannelRef.isValidId(id)) return null;
  return () => controller.openChannel(ChannelRef(id, message.author.replaceFirst(RegExp(r'^@'), '')));
}

/// The switch for [superChatHighlights] over the chat.
class SuperChatHighlightSwitch extends StatelessWidget {
  const SuperChatHighlightSwitch({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final on = controller.preferences.superChatHighlights;
    return IconButton(
      tooltip: on ? tr('Super Chats in colour and pinned on top: on') : tr('Super Chats in colour and pinned on top: off'),
      isSelected: on,
      icon: Icon(on ? AppIcons.handHeartFill : AppIcons.handHeart, size: 18),
      onPressed: () {
        superChatHighlights.value = !on;
        unawaited(controller.savePreferences(controller.preferences.copyWith(superChatHighlights: !on)));
      },
    );
  }
}

/// One message of a live chat or chat replay: the author's picture and
/// name, which open their channel, and a Super Chat in its tier's colour.
class ChatMessageRow extends StatelessWidget {
  const ChatMessageRow({super.key, required this.controller, required this.message, this.onSeek});
  final AppController controller;
  final LiveChatMessage message;
  final VoidCallback? onSeek;

  @override
  Widget build(BuildContext context) {
    final color = message.color;
    if (color == null) return _build(context, null);
    return ValueListenableBuilder(valueListenable: superChatHighlights, builder: (context, on, _) => _build(context, on ? Color(color) : null));
  }

  Widget _build(BuildContext context, Color? tier) {
    final colors = context.colors;
    final time = message.offset == null ? '' : chatClock(message.offset!);
    final openAuthor = _openAuthor(controller, message);
    final name = message.author.isEmpty ? tr('System message') : message.author;
    final Widget picture = switch (message.kind) {
      LiveChatKind.system => Icon(AppIcons.info, size: 20, color: colors.outline),
      _ => InkWell(
          customBorder: const CircleBorder(),
          onTap: openAuthor,
          child: ChannelAvatar(name: name.replaceFirst(RegExp(r'^@'), ''), image: message.authorAvatar, radius: 12),
        ),
    };
    final kindIcon = switch (message.kind) {
      LiveChatKind.paidMessage => AppIcons.handHeartFill,
      LiveChatKind.paidSticker => AppIcons.smileySticker,
      LiveChatKind.membership => AppIcons.medal,
      _ => null,
    };
    final amount = message.amount;
    final row = Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      picture,
      const SizedBox(width: 8),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          if (kindIcon != null) Padding(padding: const EdgeInsets.only(right: 4), child: Icon(kindIcon, size: 14, color: tier ?? colors.outline)),
          Flexible(
            child: MouseRegion(
              cursor: openAuthor == null ? MouseCursor.defer : SystemMouseCursors.click,
              child: GestureDetector(
                onTap: openAuthor,
                child: Text(name, style: const TextStyle(fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ),
          ),
          const Spacer(),
          if (amount != null)
            tier == null
                ? Text(amount, style: TextStyle(color: colors.primary, fontWeight: FontWeight.w700))
                : Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(color: tier, borderRadius: BorderRadius.circular(6)),
                    child: Text(amount, style: TextStyle(color: _onTier(tier), fontWeight: FontWeight.w700, fontSize: 12)),
                  ),
          if (time.isNotEmpty) Padding(padding: const EdgeInsets.only(left: 8), child: Text(time, style: TextStyle(color: colors.outline, fontSize: 12))),
        ]),
        if (message.text.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: SelectionArea(child: Text.rich(TextSpan(children: emojiSpans(context, message.text, message.emojis))))),
        if (message.text.isNotEmpty) ChatMessageTranslation(controller: controller, message: message),
        if (message.stickerUrl != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Image.network(
              color: context.pictureWarmth,
              colorBlendMode: BlendMode.multiply,
              message.stickerUrl!,
              height: 56,
              cacheHeight: (56 * MediaQuery.devicePixelRatioOf(context)).round(),
              errorBuilder: (context, error, stack) => const SizedBox.shrink(),
            ),
          ),
      ])),
    ]);
    return ChatMessageTranslateButton(message: message, child: InkWell(
      onTap: onSeek,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        decoration: tier == null
            ? null
            : BoxDecoration(
                color: tier.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border(left: BorderSide(color: tier, width: 3)),
              ),
        child: row,
      ),
    ));
  }
}

/// `1:23` or `1:02:03`.
String chatClock(Duration value) {
  final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
  return value.inHours > 0 ? '${value.inHours}:${value.inMinutes.remainder(60).toString().padLeft(2, '0')}:$seconds' : '${value.inMinutes}:$seconds';
}

/// The recent Super Chats of a live chat in a row over it, as on YouTube:
/// each stays as long as its amount buys; one tapped shows in full.
class SuperChatStrip extends StatefulWidget {
  const SuperChatStrip({super.key, required this.controller});
  final AppController controller;

  @override
  State<SuperChatStrip> createState() => _SuperChatStripState();
}

class _SuperChatStripState extends State<SuperChatStrip> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // Ones whose time ran out leave even when the chat is quiet.
    _tick = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final items = [for (final (message, until) in widget.controller.chatTicker) if (until.isAfter(now) && message.color != null) message];
    if (items.isEmpty || !widget.controller.preferences.superChatHighlights) return const SizedBox.shrink();
    return SizedBox(
      height: 32,
      child: ListView.separated(
        primary: false,
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (context, _) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final message = items[index];
          final tier = Color(message.color!);
          return Material(
            color: tier,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => showDialog<void>(
                context: context,
                builder: (context) => Dialog(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 360),
                    child: Padding(padding: const EdgeInsets.all(12), child: ChatMessageRow(controller: widget.controller, message: message)),
                  ),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 10, 4),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  ChannelAvatar(name: message.author.replaceFirst(RegExp(r'^@'), ''), image: message.authorAvatar, radius: 12),
                  const SizedBox(width: 6),
                  Text(message.amount ?? '', style: TextStyle(color: _onTier(tier), fontWeight: FontWeight.w700, fontSize: 12)),
                ]),
              ),
            ),
          );
        },
      ),
    );
  }
}
