import 'dart:async';

import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../skins/skin.dart';
import '../window_frame.dart';
import 'skin_chrome.dart';
import 'skin_paint.dart';
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
  late final _changes = Listenable.merge([widget.controller, WindowChrome.menus, WindowChrome.fullscreen]);

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
          // Picture in picture shows the video alone, in its own frame.
          if (c.pip && c.playing != null && c.videoController != null) return child!;
          final appearance = c.appearance;
          final bare = WindowChrome.fullscreen.value;
          final ownTitleBar = usesSkinTitleBar(skin, systemTitleBar: appearance.systemTitleBar);
          _useCustomFrame(ownTitleBar);
          final menuBar = !bare && WindowFrame.supported && !appearance.systemTitleBar ? skin?.menuBar : null;
          final menus = menuBar == null ? const <SkinMenu>[] : WindowChrome.menus.value?.call(appMenu: menuBar.appMenu) ?? const <SkinMenu>[];
          Widget menuView(SkinMenuBar bar) => CallbackShortcuts(bindings: menuShortcuts(menus), child: SkinMenuBarView(bar: bar, menus: menus, clock: bar.clock));
          Widget content = Column(children: [
            if (menuBar case final bar? when bar.top && menus.isNotEmpty) menuView(bar),
            if (ownTitleBar && !bare) SkinTitleBarView(bar: skin!.titleBar!, title: widget.title),
            if (menuBar case final bar? when !bar.top && menus.isNotEmpty) menuView(bar),
            Expanded(child: child!),
          ]);
          if (skin != null) content = SkinBackdrop(skin: skin, plain: appearance.lowResource, child: content);
          if (ownTitleBar && !bare) content = ResizeEdges(child: content);
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
