part of 'player_controls.dart';

/// A button of the bars: focusable from the keyboard, lit under the mouse,
/// ringed when it has keyboard focus.
class _Pressable extends StatefulWidget {
  const _Pressable({required this.tooltip, required this.onTap, required this.child, this.width, this.height, this.padding});
  final String tooltip;
  final VoidCallback onTap;
  final Widget child;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry? padding;

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _hover = false;
  bool _focused = false;

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter || key == LogicalKeyboardKey.select) {
      widget.onTap();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final ring = _focused && FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
    final lit = _hover || ring;
    return Tooltip(
      message: widget.tooltip,
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        label: widget.tooltip,
        onTap: widget.onTap,
        excludeSemantics: true,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: Focus(
            onFocusChange: (focused) => setState(() => _focused = focused),
            onKeyEvent: _onKey,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onTap,
              child: AnimatedContainer(
                duration: Motion.of(Ease.press),
                width: widget.width,
                height: widget.height,
                padding: widget.padding,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: lit ? const Color(0x24FFFFFF) : Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                  border: ring ? Border.all(color: const Color(0xBFFFFFFF), width: 2) : null,
                ),
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  const _IconBtn({required this.icon, required this.tooltip, required this.onTap, this.size = 22, this.width = 34, this.active = false});
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final double size;
  final double width;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final touch = touchFirst;
    return _Pressable(
      tooltip: tooltip,
      onTap: onTap,
      width: touch ? math.max(width, 44.0) : width,
      height: touch ? 44 : 34,
      child: Icon(icon, size: size, color: active ? Theme.of(context).colorScheme.inversePrimary : Colors.white),
    );
  }
}

/// A round button over the picture, such as the lock.
class _CircleButton extends StatelessWidget {
  const _CircleButton({required this.icon, required this.tooltip, required this.onTap, this.active = false, this.accent});
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool active;
  final Color? accent;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: const BoxDecoration(color: Color(0x66000000), shape: BoxShape.circle),
        child: _Pressable(
          tooltip: tooltip,
          onTap: onTap,
          width: 40,
          height: 40,
          child: Icon(icon, size: 22, color: active ? accent ?? Theme.of(context).colorScheme.inversePrimary : Colors.white),
        ),
      );
}

/// Like, comments, favourites and share in a phone's landscape top bar.
class _CountButton extends StatelessWidget {
  const _CountButton({required this.icon, required this.tooltip, required this.onTap, this.count, this.active = false});
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final int? count;
  final bool active;

  @override
  Widget build(BuildContext context) => _Pressable(
        tooltip: tooltip,
        onTap: onTap,
        width: 52,
        height: 44,
        child: Stack(alignment: Alignment.center, children: [
          Icon(icon, size: 24, color: active ? Theme.of(context).colorScheme.inversePrimary : Colors.white),
          if (count != null)
            PositionedDirectional(
              start: 30,
              top: 0,
              child: Text(
                formatCount(count!),
                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600, shadows: [Shadow(blurRadius: 3, color: Colors.black87)]),
              ),
            ),
        ]),
      );
}

/// The wait indicator in the middle of the picture.
class _Buffering extends StatelessWidget {
  const _Buffering({required this.player, required this.c});
  final Player player;
  final AppController c;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: StreamBuilder<bool>(
        stream: player.stream.buffering,
        initialData: player.state.buffering,
        builder: (context, snapshot) => ListenableBuilder(
          listenable: c,
          builder: (context, _) {
            final waiting = c.waitingForSubtitles;
            if (!((snapshot.data ?? false) || waiting) || c.playbackError != null) return const SizedBox.shrink();
            return Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const SizedBox(width: 36, height: 36, child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white)),
                if (waiting) ...[
                  const SizedBox(height: 12),
                  Text(tr('Translating subtitles…'), style: const TextStyle(color: Colors.white, shadows: [Shadow(blurRadius: 4, color: Colors.black)])),
                ],
              ]),
            );
          },
        ),
      ),
    );
  }
}

class _FeedbackBubble extends StatelessWidget {
  const _FeedbackBubble({required this.feedback});
  final ValueListenable<({IconData icon, String text})?> feedback;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
        valueListenable: feedback,
        builder: (context, value, _) {
          if (value == null) return const SizedBox.shrink();
          return Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: const Color(0x88000000), borderRadius: BorderRadius.circular(8)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(value.icon, size: 22, color: Colors.white),
                const SizedBox(width: 4),
                Text(value.text, style: const TextStyle(color: Colors.white, fontSize: 12)),
              ]),
            ),
          );
        },
      );
}
