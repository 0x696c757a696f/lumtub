import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../skins/skin.dart';
import '../window_frame.dart';
import 'app_icons.dart';
import 'skin_paint.dart';
import 'theme.dart';

/// The app's name drawn as a skin's logo says: a badge with the play
/// triangle and the name in the skin's letters.
class SkinWordmark extends StatelessWidget {
  const SkinWordmark({super.key, required this.skin, required this.name, this.showName = true});
  final Skin skin;
  final String name;
  final bool showName;

  @override
  Widget build(BuildContext context) {
    final logo = skin.logo;
    final colors = context.colors;
    final size = logo.size ?? 22;
    final badge = SizedBox(
      width: 30,
      height: 30,
      child: SkinBox(
        surface: logo.badge ?? SkinSurfaceDefaults.badge(colors.primary),
        radius: 15,
        child: Icon(AppIcons.playFill, color: logo.badgeIcon ?? colors.onPrimary, size: 18),
      ),
    );
    if (!showName) return badge;
    final style = TextStyle(
      fontFamily: logo.font ?? skin.displayFont,
      fontFamilyFallback: const ['Noto Sans CJK SC'],
      fontSize: size,
      height: 1,
      fontWeight: FontWeight.w700,
      color: colors.onSurface,
      shadows: [
        if (logo.shadow case final c?) Shadow(color: c, offset: const Offset(0, 1.5)),
        if (logo.glow case final c?) Shadow(color: c, blurRadius: 10),
      ],
    );
    final text = logo.text ?? name;
    Widget word = Text(text, style: style);
    if (logo.fill.isNotEmpty) {
      word = ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (bounds) {
          final layer = logo.fill.last;
          return switch (layer) {
            LinearPaint() => layer.gradient.createShader(bounds),
            RadialPaint(:final colors, :final stops) => RadialGradient(colors: colors, stops: stops).createShader(bounds),
            SolidPaint(:final color) => LinearGradient(colors: [color, color]).createShader(bounds),
            _ => const LinearGradient(colors: [Colors.white, Colors.white]).createShader(bounds),
          };
        },
        child: word,
      );
    }
    if (logo.stroke case final stroke?) {
      word = Stack(children: [
        Text(text, style: style.copyWith(
          shadows: const [],
          foreground: Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2
            ..color = stroke,
        )),
        word,
      ]);
    }
    return Row(mainAxisSize: MainAxisSize.min, children: [badge, const SizedBox(width: 10), word]);
  }
}

abstract final class SkinSurfaceDefaults {
  static final _badges = <Color, SkinSurface>{};

  /// The plain badge of skins that do not draw one: the accent, with a shine.
  static SkinSurface badge(Color accent) => _badges.putIfAbsent(accent, () => SkinSurface.solid(accent, gloss: 0.5));
}

/// The title bar a skin draws, with minimise, maximise and close at the
/// right. Dragging it moves the window and a double click maximises it;
/// on Windows the system does both from the caption area reported to it,
/// which keeps snapping and Windows 11's snap layouts.
class SkinTitleBarView extends StatefulWidget {
  const SkinTitleBarView({super.key, required this.bar, required this.title});
  final SkinTitleBar bar;
  final String title;

  @override
  State<SkinTitleBarView> createState() => _SkinTitleBarViewState();
}

class _SkinTitleBarViewState extends State<SkinTitleBarView> {
  final _minimize = GlobalKey();
  final _maximize = GlobalKey();
  final _close = GlobalKey();

  @override
  void dispose() {
    if (Platform.isWindows) WindowFrame.setCaption(height: 0);
    super.dispose();
  }

  Rect? _rectOf(GlobalKey key) {
    final box = key.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  void _report() {
    if (!Platform.isWindows || !mounted) return;
    final max = _rectOf(_maximize);
    WindowFrame.setCaption(
      height: widget.bar.height,
      maximizeButton: max,
      interactive: [_rectOf(_minimize), _rectOf(_close)].nonNulls.toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _report());
    final bar = widget.bar;
    return ValueListenableBuilder(
      valueListenable: WindowFrame.active,
      builder: (context, active, _) {
        final surface = active ? bar.surface : bar.inactive ?? bar.surface;
        final text = active ? bar.text : bar.inactiveText ?? bar.text.withValues(alpha: 0.6);
        final title = Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: text, fontSize: 13, fontWeight: FontWeight.w700));
        final buttons = Row(mainAxisSize: MainAxisSize.min, children: [
          _WindowButton(key: _minimize, bar: bar, icon: _Glyph.minimize, tooltip: MaterialLocalizations.of(context).collapsedHint, onPressed: WindowFrame.minimize),
          const SizedBox(width: 2),
          ValueListenableBuilder(
            valueListenable: WindowFrame.maximized,
            builder: (context, maximized, _) => ValueListenableBuilder(
              valueListenable: WindowFrame.maximizeButton,
              builder: (context, state, _) => _WindowButton(
                key: _maximize,
                bar: bar,
                icon: maximized ? _Glyph.restore : _Glyph.maximize,
                onPressed: WindowFrame.toggleMaximize,
                forced: state,
              ),
            ),
          ),
          const SizedBox(width: 2),
          _WindowButton(key: _close, bar: bar, icon: _Glyph.close, close: true, onPressed: WindowFrame.close),
        ]);
        final row = Row(children: [
          if (bar.icon) ...[
            const SizedBox(width: 6),
            Icon(AppIcons.playFill, size: 16, color: text),
          ],
          const SizedBox(width: 8),
          Expanded(child: bar.align == 'center' ? Center(child: title) : title),
          buttons,
          const SizedBox(width: 3),
        ]);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          // On Windows the system moves the window from the caption itself.
          onPanStart: Platform.isWindows ? null : (_) => unawaited(WindowFrame.startDrag()),
          onDoubleTap: Platform.isWindows ? null : () => unawaited(WindowFrame.toggleMaximize()),
          child: SizedBox(height: bar.height, child: SkinBox(surface: surface, child: row)),
        );
      },
    );
  }
}

enum _Glyph { minimize, maximize, restore, close }

class _WindowButton extends StatefulWidget {
  const _WindowButton({super.key, required this.bar, required this.icon, required this.onPressed, this.close = false, this.forced, this.tooltip});
  final SkinTitleBar bar;
  final _Glyph icon;
  final Future<void> Function() onPressed;
  final bool close;
  /// The state Windows reports for the maximise button, which it owns.
  final WindowButtonState? forced;
  final String? tooltip;

  @override
  State<_WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<_WindowButton> {
  bool _hover = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final bar = widget.bar;
    final forced = widget.forced ?? WindowButtonState.none;
    final hovered = _hover || forced == WindowButtonState.hover;
    final pressed = _pressed || forced == WindowButtonState.pressed;
    final base = widget.close ? bar.closeButton ?? bar.button : bar.button;
    final surface = base?.forState(hovered: hovered, pressed: pressed);
    final size = bar.buttonSize;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() {
        _hover = false;
        _pressed = false;
      }),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: () {
          setState(() => _pressed = false);
          unawaited(widget.onPressed());
        },
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: SkinBox(
            surface: surface,
            child: DecoratedBox(
              // Without a skinned button, a plain wash shows the pointer.
              decoration: BoxDecoration(color: surface != null || !(hovered || pressed) ? null : (widget.close ? const Color(0xFFE81123) : bar.buttonIcon.withValues(alpha: pressed ? 0.2 : 0.1))),
              child: CustomPaint(painter: _GlyphPainter(widget.icon, widget.close && surface == null && hovered ? Colors.white : bar.buttonIcon)),
            ),
          ),
        ),
      ),
    );
  }
}

/// The window buttons' signs, in pixel lines so they stay crisp in any skin.
class _GlyphPainter extends CustomPainter {
  _GlyphPainter(this.glyph, this.color);
  final _Glyph glyph;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke
      ..isAntiAlias = glyph == _Glyph.close;
    final c = size.center(Offset.zero);
    const s = 5.0;
    switch (glyph) {
      case _Glyph.minimize:
        canvas.drawLine(c + const Offset(-s, s * 0.6), c + const Offset(s, s * 0.6), p..strokeWidth = 2);
      case _Glyph.maximize:
        canvas.drawRect(Rect.fromCenter(center: c, width: s * 2, height: s * 2), p);
        canvas.drawLine(c + const Offset(-s, -s + 1), c + const Offset(s, -s + 1), p..strokeWidth = 2);
      case _Glyph.restore:
        canvas.drawRect(Rect.fromLTWH(c.dx - s, c.dy - s + 3, s * 2 - 3, s * 2 - 3), p);
        canvas.drawPath(Path()
          ..moveTo(c.dx - s + 3, c.dy - s + 3)
          ..lineTo(c.dx - s + 3, c.dy - s)
          ..lineTo(c.dx + s, c.dy - s)
          ..lineTo(c.dx + s, c.dy + s - 3)
          ..lineTo(c.dx + s - 3, c.dy + s - 3), p);
      case _Glyph.close:
        canvas.drawLine(c + const Offset(-s, -s), c + const Offset(s, s), p..strokeWidth = 1.6);
        canvas.drawLine(c + const Offset(s, -s), c + const Offset(-s, s), p);
    }
  }

  @override
  bool shouldRepaint(_GlyphPainter old) => old.glyph != glyph || old.color != color;
}

/// One menu of [SkinMenuBarView]: '&' marks the letter Alt opens it with.
class SkinMenu {
  const SkinMenu(this.label, this.entries);
  final String label;
  final List<SkinMenuEntry> entries;
}

class SkinMenuEntry {
  const SkinMenuEntry(this.label, this.onPressed, {this.shortcut, this.checked});
  const SkinMenuEntry.divider()
      : label = '',
        onPressed = null,
        shortcut = null,
        checked = null;
  final String label;
  final VoidCallback? onPressed;
  final SingleActivator? shortcut;
  final bool? checked;
  bool get isDivider => label.isEmpty;
}

/// The text menus under the title bar, drawn by the app in the skin's
/// colours: Alt and a menu's underlined letter open it, arrows move.
class SkinMenuBarView extends StatelessWidget {
  const SkinMenuBarView({super.key, required this.bar, required this.menus, this.clock = false});
  final SkinMenuBar bar;
  final List<SkinMenu> menus;
  final bool clock;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final menuSurface = bar.menu;
    final menuColor = menuSurface?.baseColor ?? colors.surface;
    final highlight = bar.highlight?.baseColor ?? colors.primary;
    final highlightText = bar.highlightText ?? colors.onPrimary;
    final itemText = ThemeData.estimateBrightnessForColor(Color.alphaBlend(menuColor, colors.surface)) == Brightness.dark ? Colors.white : Colors.black;
    final itemStyle = ButtonStyle(
      foregroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.disabled)
          ? itemText.withValues(alpha: 0.4)
          : s.contains(WidgetState.hovered) || s.contains(WidgetState.focused)
              ? highlightText
              : itemText),
      backgroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.hovered) || s.contains(WidgetState.focused) ? highlight : null),
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      shape: const WidgetStatePropertyAll(RoundedRectangleBorder()),
      minimumSize: const WidgetStatePropertyAll(Size(180, 30)),
      textStyle: const WidgetStatePropertyAll(TextStyle(fontSize: 13)),
    );
    final barStyle = ButtonStyle(
      foregroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.hovered) || s.contains(WidgetState.focused) || s.contains(WidgetState.pressed) ? highlightText : bar.text),
      backgroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.hovered) || s.contains(WidgetState.focused) || s.contains(WidgetState.pressed) ? highlight : Colors.transparent),
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      shape: const WidgetStatePropertyAll(RoundedRectangleBorder()),
      padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 10)),
      minimumSize: const WidgetStatePropertyAll(Size(0, 24)),
      textStyle: const WidgetStatePropertyAll(TextStyle(fontSize: 13)),
    );
    final menuStyle = MenuStyle(
      backgroundColor: WidgetStatePropertyAll(menuColor),
      elevation: const WidgetStatePropertyAll(4),
      shape: WidgetStatePropertyAll(RoundedRectangleBorder(side: BorderSide(color: menuSurface?.border ?? colors.outline))),
      padding: const WidgetStatePropertyAll(EdgeInsets.all(2)),
    );
    Widget label(String text) => bar.underlineKeys ? MenuAcceleratorLabel(text) : Text(text.replaceAll('&', ''));
    return SkinBox(
      surface: bar.surface,
      child: SizedBox(
        height: 26,
        child: Row(children: [
          Expanded(child: MenuBar(
            style: const MenuStyle(
              backgroundColor: WidgetStatePropertyAll(Colors.transparent),
              elevation: WidgetStatePropertyAll(0),
              padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 4)),
              shape: WidgetStatePropertyAll(RoundedRectangleBorder()),
            ),
            children: [
              for (final menu in menus)
                SubmenuButton(
                  style: barStyle,
                  menuStyle: menuStyle,
                  menuChildren: [
                    for (final entry in menu.entries)
                      if (entry.isDivider)
                        Divider(height: 7, indent: 4, endIndent: 4, color: itemText.withValues(alpha: 0.3))
                      else
                        MenuItemButton(
                          style: itemStyle,
                          onPressed: entry.onPressed,
                          shortcut: entry.shortcut,
                          leadingIcon: entry.checked == null ? const SizedBox(width: 16) : Icon(entry.checked! ? AppIcons.check : null, size: 16),
                          child: label(entry.label),
                        ),
                  ],
                  child: label(menu.label),
                ),
            ],
          )),
          if (clock) Padding(padding: const EdgeInsets.only(right: 10), child: _Clock(color: bar.text)),
        ]),
      ),
    );
  }
}

class _Clock extends StatefulWidget {
  const _Clock({required this.color});
  final Color color;

  @override
  State<_Clock> createState() => _ClockState();
}

class _ClockState extends State<_Clock> {
  late final Timer _timer = Timer.periodic(const Duration(seconds: 15), (_) => setState(() {}));

  @override
  void initState() {
    super.initState();
    _timer;
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = TimeOfDay.now();
    return Text(MaterialLocalizations.of(context).formatTimeOfDay(now, alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context)),
        style: TextStyle(color: widget.color, fontSize: 13, fontFeatures: const [FontFeature.tabularFigures()]));
  }
}

/// The side rail as a skin draws it: its own surface, and the chosen
/// page on [Skin.navSelected].
class SkinRail extends StatelessWidget {
  const SkinRail({super.key, required this.skin, required this.destinations, required this.selected, required this.onSelected});
  final Skin skin;
  final List<(IconData, IconData, String)> destinations;
  final int? selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final radius = context.controlRadius.topLeft.x;
    return SkinBox(
      surface: skin.sideBar,
      child: SizedBox(
        width: 84,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: Space.m, horizontal: Space.s),
          child: Column(children: [
            for (var i = 0; i < destinations.length; i++) ...[
              _RailItem(
                icon: i == selected ? destinations[i].$2 : destinations[i].$1,
                label: destinations[i].$3,
                selected: i == selected,
                surface: i == selected ? skin.navSelected ?? _wash(colors) : null,
                color: i == selected ? skin.navSelectedText ?? colors.onSurface : skin.navText ?? colors.onSurfaceVariant,
                radius: radius,
                onTap: () => onSelected(i),
              ),
              const SizedBox(height: Space.xs),
            ],
          ]),
        ),
      ),
    );
  }

  SkinSurface _wash(ColorScheme colors) => SkinSurface.solid(colors.secondaryContainer);
}

class _RailItem extends StatefulWidget {
  const _RailItem({required this.icon, required this.label, required this.selected, required this.surface, required this.color, required this.radius, required this.onTap});
  final IconData icon;
  final String label;
  final bool selected;
  final SkinSurface? surface;
  final Color color;
  final double radius;
  final VoidCallback onTap;

  @override
  State<_RailItem> createState() => _RailItemState();
}

class _RailItemState extends State<_RailItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: widget.selected,
        label: widget.label,
        child: FocusableActionDetector(
          mouseCursor: SystemMouseCursors.click,
          onShowHoverHighlight: (v) => setState(() => _hover = v),
          actions: {ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) => widget.onTap())},
          child: GestureDetector(
            onTap: widget.onTap,
            child: SkinBox(
              surface: widget.surface?.forState(hovered: _hover),
              radius: widget.radius,
              child: Container(
                color: widget.surface == null && _hover ? widget.color.withValues(alpha: 0.08) : null,
                padding: const EdgeInsets.symmetric(vertical: Space.s),
                width: double.infinity,
                child: Column(children: [
                  Icon(widget.icon, color: widget.color, size: 22),
                  const SizedBox(height: 2),
                  Text(widget.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: widget.color, fontWeight: widget.selected ? FontWeight.w700 : null)),
                ]),
              ),
            ),
          ),
        ),
      );
}

/// Linux draws no frame round a window without the system title bar, so
/// its edges and corners are made to resize it here.
class ResizeEdges extends StatelessWidget {
  const ResizeEdges({super.key, required this.child});
  final Widget child;

  static const _edge = 5.0;

  @override
  Widget build(BuildContext context) {
    if (!Platform.isLinux) return child;
    return ValueListenableBuilder(
      valueListenable: WindowFrame.maximized,
      builder: (context, maximized, child) => maximized
          ? child!
          : Stack(children: [
              child!,
              _zone(WindowEdge.top, SystemMouseCursors.resizeUp, top: 0, left: _edge, right: _edge, height: _edge),
              _zone(WindowEdge.bottom, SystemMouseCursors.resizeDown, bottom: 0, left: _edge, right: _edge, height: _edge),
              _zone(WindowEdge.left, SystemMouseCursors.resizeLeft, left: 0, top: _edge, bottom: _edge, width: _edge),
              _zone(WindowEdge.right, SystemMouseCursors.resizeRight, right: 0, top: _edge, bottom: _edge, width: _edge),
              _zone(WindowEdge.topLeft, SystemMouseCursors.resizeUpLeft, top: 0, left: 0, width: _edge * 2, height: _edge * 2),
              _zone(WindowEdge.topRight, SystemMouseCursors.resizeUpRight, top: 0, right: 0, width: _edge * 2, height: _edge * 2),
              _zone(WindowEdge.bottomLeft, SystemMouseCursors.resizeDownLeft, bottom: 0, left: 0, width: _edge * 2, height: _edge * 2),
              _zone(WindowEdge.bottomRight, SystemMouseCursors.resizeDownRight, bottom: 0, right: 0, width: _edge * 2, height: _edge * 2),
            ]),
      child: child,
    );
  }

  Widget _zone(WindowEdge edge, MouseCursor cursor, {double? top, double? bottom, double? left, double? right, double? width, double? height}) => Positioned(
        top: top,
        bottom: bottom,
        left: left,
        right: right,
        width: width,
        height: height,
        child: MouseRegion(
          cursor: cursor,
          child: GestureDetector(behavior: HitTestBehavior.opaque, onPanStart: (_) => unawaited(WindowFrame.startResize(edge))),
        ),
      );
}

/// Whether [skin]'s own title bar is in use.
bool usesSkinTitleBar(Skin? skin, {required bool systemTitleBar}) => skin?.titleBar != null && !systemTitleBar && WindowFrame.supported;

/// Keyboard shortcuts of the menus also work while the menus are closed.
Map<ShortcutActivator, VoidCallback> menuShortcuts(List<SkinMenu> menus) => {
      for (final menu in menus)
        for (final entry in menu.entries)
          if (entry.shortcut != null && entry.onPressed != null) entry.shortcut!: entry.onPressed!,
    };
