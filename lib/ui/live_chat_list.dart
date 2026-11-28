import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../l10n/l10n.dart';
import '../live_chat.dart';
import 'app_icons.dart';
import 'motion.dart';

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

  /// The newest message shown while scrolled up; null while following.
  /// Held by the message itself, not by a count: once the chat is at its
  /// cap the count stays the same as the oldest are dropped.
  LiveChatMessage? _held;
  bool _holding = false;

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
    if (away && !_holding) {
      setState(() {
        _holding = true;
        _held = widget.messages.lastOrNull;
      });
    } else if (!away && _holding) {
      setState(() {
        _holding = false;
        _held = null;
      });
    }
  }

  void _toLatest() {
    setState(() {
      _holding = false;
      _held = null;
    });
    if (_scroll.hasClients) {
      unawaited(Motion.scrollTo(_scroll, 0,
          duration: const Duration(milliseconds: 250), curve: Curves.easeOut));
    }
  }

  /// How many messages, from the oldest, show while held.
  int _shown(List<LiveChatMessage> messages) {
    if (!_holding) return messages.length;
    final held = _held;
    if (held == null) return 0;
    for (var i = messages.length - 1; i >= 0; i--) {
      final m = messages[i];
      if (identical(m, held) || (held.id.isNotEmpty && m.id == held.id)) return i + 1;
    }
    // Dropped as the list is capped: nothing shown is left to hold.
    return messages.length;
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.messages.length;
    final shown = _shown(widget.messages);
    final waiting = total - shown;
    return Stack(children: [
      ListView.builder(
        controller: _scroll,
        reverse: true,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        itemCount: shown,
        itemBuilder: (context, index) => widget.messageAt(shown - 1 - index),
      ),
      if (_holding)
        Positioned(
          left: 0,
          right: 0,
          bottom: 8,
          child: Center(
            child: FilledButton.tonalIcon(
              onPressed: _toLatest,
              icon: Icon(AppIcons.caretDown, size: 16),
              label:
                  Text(waiting > 0 ? tr('{0} new messages', [waiting]) : tr('Back to the latest')),
            ),
          ),
        ),
    ]);
  }
}
