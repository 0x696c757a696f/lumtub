import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../app/app_controller.dart';
import '../skins/skin.dart';
import '../window_frame.dart';
import 'glass_look.dart';
import 'skin_chrome.dart';
import 'skin_paint.dart';
import 'theater_mode.dart';
import 'theme.dart';

/// What a skin draws round every page: its backdrop, its title bar and
/// menu bar, and the edges that resize the window. It sits above the
/// navigator, so the settings and other pages opened over the main window
/// keep the same frame and background.
class WindowChrome extends StatefulWidget {
  const WindowChrome({super.key, required this.controller, required this.title, required this.child});
  final AppController controller;
  final String title;
  final Widget child;

  /// Builds the menu bar's menus; the main window sets it, since the menus
  /// act on what it shows.
  static final menus = ValueNotifier<List<SkinMenu> Function({required bool appMenu})?>(null);

  /// The video fills the screen: the frame steps aside.
  static final fullscreen = ValueNotifier<bool>(false);

  @override
  State<WindowChrome> createState() => _WindowChromeState();
}

class _WindowChromeState extends State<WindowChrome> {
  bool? _customFrame;
  late final _changes = Listenable.merge([widget.controller, WindowChrome.menus, WindowChrome.fullscreen, fillingWindow]);

  /// Takes the system title bar away while a skin draws its own, and gives
  /// it back when not.
  void _useCustomFrame(bool on) {
    if (_customFrame == on || (!on && _customFrame == null)) {
      _customFrame = on;
      return;
    }
    _customFrame = on;
    unawaited(WindowFrame.setCustom(on));
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: _changes,
        builder: (context, child) {
          final c = widget.controller;
          final skin = context.skin;
          final glass = context.glass;
          // Picture in picture shows the video alone, in its own frame,
          // solid even while the window is glass.
          if (c.pip && c.playing != null && c.videoController != null) return glass == null ? child! : ColoredBox(color: Colors.black, child: child);
          final appearance = c.appearance;
          // 铺满窗口 takes the system title bar away too, so only the video
          // is left in the window; leaving it brings the bar back.
          final filling = fillingWindow.value && WindowFrame.supported;
          final bare = WindowChrome.fullscreen.value || filling;
          final ownTitleBar = usesSkinTitleBar(skin, systemTitleBar: appearance.systemTitleBar);
          _useCustomFrame(ownTitleBar || filling);
          final menuBar = !bare && WindowFrame.supported && !appearance.systemTitleBar ? skin?.menuBar : null;
          final menus = menuBar == null ? const <SkinMenu>[] : WindowChrome.menus.value?.call(appMenu: menuBar.appMenu) ?? const <SkinMenu>[];
          Widget menuView(SkinMenuBar bar) => CallbackShortcuts(bindings: menuShortcuts(menus), child: SkinMenuBarView(bar: bar, menus: menus, clock: bar.clock));
          // With the title bar hidden, the menu bar takes its place and
          // holds the window buttons.
          final merged = ownTitleBar && !bare && appearance.hideTitleBar && menuBar != null && menus.isNotEmpty;
          Widget content = Column(children: [
            if (merged)
              SkinTitleBarView(
                bar: skin!.titleBar!,
                title: widget.title,
                menuBar: menuBar,
                menus: CallbackShortcuts(bindings: menuShortcuts(menus), child: SkinMenuBarView(bar: menuBar, menus: menus, clock: menuBar.clock, embedded: true)),
              )
            else ...[
              if (menuBar case final bar? when bar.top && menus.isNotEmpty) menuView(bar),
              if (ownTitleBar && !bare) SkinTitleBarView(bar: skin!.titleBar!, title: widget.title),
              if (menuBar case final bar? when !bar.top && menus.isNotEmpty) menuView(bar),
            ],
            Expanded(child: child!),
          ]);
          if (skin != null) {
            content = SkinBackdrop(skin: skin, plain: appearance.lowResource, pictures: appearance.skinBackground, child: content);
          } else if (glass != null) {
            // The standard look has no backdrop of its own, only its page
            // colour, which the glass takes.
            content = Stack(fit: StackFit.expand, children: [GlassBackdrop(look: glass, plain: appearance.lowResource), content]);
          }
          // Filling the window still leaves it a window: its edges size it.
          // (Windows and macOS keep their own sizing borders; ResizeEdges
          // only draws them where the desktop takes them away.)
          if ((ownTitleBar && !bare) || (filling && !WindowChrome.fullscreen.value)) content = ResizeEdges(child: content);
          // Above the navigator there is no page yet: the bars get the text
          // style and ink a page would give them, and an overlay of their
          // own for their menus and tooltips.
          return Overlay.wrap(
            child: Material(
              type: MaterialType.transparency,
              textStyle: Theme.of(context).textTheme.bodyMedium,
              child: content,
            ),
          );
        },
        child: widget.child,
      );
}
