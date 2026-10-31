import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../live_chat.dart';
import 'app_icons.dart';

/// The live chat, newest at the bottom, following new messages as YouTube's
/// and Twitch's chats do: scrolled up to read, it holds still and offers
/// the new messages behind a button instead.
class LiveChatList extends StatefulWidget {
  const LiveChatList({super.key, required this.messages, required this.messageAt});
  final List<LiveChatMessage> messages;
  final Widget Function(int index) messageAt;

  @override
  State<LiveChatList> createState() => LiveChatListState();
}

class LiveChatListState extends State<LiveChatList> {
  final _scroll = ScrollController();
  /// How many messages show while scrolled up; null while following.
  int? _held;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_scrolled);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _scrolled() {
    final away = _scroll.offset > 48;
    if (away && _held == null) {
      setState(() => _held = widget.messages.length);
    } else if (!away && _held != null) {
      setState(() => _held = null);
    }
  }

  void _toLatest() {
    setState(() => _held = null);
    if (_scroll.hasClients) _scroll.animateTo(0, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.messages.length;
    // The oldest are dropped as the list is capped, so what was held may
    // now be fewer.
    final shown = (_held ?? total).clamp(0, total);
    final waiting = total - shown;
    return Stack(children: [
      ListView.builder(
        controller: _scroll,
        reverse: true,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        itemCount: shown,
        itemBuilder: (context, index) => widget.messageAt(shown - 1 - index),
      ),
      if (_held != null)
        Positioned(
          left: 0,
          right: 0,
          bottom: 8,
          child: Center(
            child: FilledButton.tonalIcon(
              onPressed: _toLatest,
              icon: const Icon(AppIcons.caretDown, size: 16),
              label: Text(waiting > 0 ? tr('{0} 条新消息', [waiting]) : tr('回到最新')),
            ),
          ),
        ),
    ]);
  }
}
