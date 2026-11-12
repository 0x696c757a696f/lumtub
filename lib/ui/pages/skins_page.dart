import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';

import '../../app/app_controller.dart';
import '../../appearance_settings.dart';
import '../../l10n/l10n.dart';
import '../../skins/skin.dart';
import '../../skins/skin_library.dart';
import '../../window_frame.dart';
import '../app_icons.dart';
import '../common.dart';
import '../motion.dart';
import '../skin_paint.dart';
import '../theme.dart';
import '../../widgets/pilinara_settings_tiles.dart';
import 'downloads_page.dart' show openInExplorer;
import '../palettes.dart' show paletteForSkin;
import 'settings_sections.dart' show themeModeTiles;
import 'settings_subpages.dart' show openColorSelect;

const _guide = 'https://github.com/0x696c757a696f/lumtub/blob/main/skins/README.md';

/// Settings › Appearance › Skins: the built-in skins, the user's own, and
/// the tools for making one.
Future<void> openSkins(BuildContext context, AppController controller) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => _SkinsPage(controller: controller)));

class _SkinsPage extends StatelessWidget {
  const _SkinsPage({required this.controller});
  final AppController controller;

  static bool get _desktop => Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  Future<void> _newSkin(BuildContext context) async {
    final library = SkinLibrary.instance;
    final folder = library.folder;
    if (folder == null) return;
    var n = 1;
    String id() => n == 1 ? 'my-skin' : 'my-skin-$n';
    while (await Directory('${folder.path}${Platform.pathSeparator}${id()}').exists()) {
      n++;
    }
    final dir = Directory('${folder.path}${Platform.pathSeparator}${id()}');
    try {
      final template = await rootBundle.loadString('skins/template/skin.jsonc');
      await dir.create(recursive: true);
      await File('${dir.path}${Platform.pathSeparator}skin.jsonc').writeAsString(template.replaceFirst('"id": "my-skin"', '"id": "${id()}"'));
      await library.reload();
      unawaited(openInExplorer(dir.path));
      if (context.mounted) _say(context, tr('Made {0}. Edit skin.jsonc in it; Lumtub shows each change when you save', [dir.path]));
    } catch (e) {
      if (context.mounted) _say(context, tr('Could not make the skin: {0}', ['$e']));
    }
  }

  @override
  Widget build(BuildContext context) {
    final library = SkinLibrary.instance;
    return Scaffold(
      appBar: SkinAppBar(AppBar(title: Text(tr('Skins')))),
      body: ListenableBuilder(
        listenable: Listenable.merge([controller, library]),
        builder: (context, _) {
          final appearance = controller.appearance;
          final language = currentLanguage.tag;
          void choose(String id) => controller.saveAppearance(controller.appearance.copyWith(skin: id));
          Widget grid(List<Skin> skins, {bool standard = false}) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Wrap(spacing: 12, runSpacing: 12, children: [
                  if (standard) SkinCard(skin: null, name: tr('Standard'), note: tr('Lumtub\'s own look'), selected: appearance.skin.isEmpty, onTap: () => choose('')),
                  for (final skin in skins)
                    SkinCard(skin: skin, name: skin.nameIn(language), note: skin.descriptionIn(language), selected: appearance.skin == skin.id, onTap: () => choose(skin.id)),
                ]),
              );
          final problems = [
            for (final skin in library.user)
              if (skin.warnings.isNotEmpty) (skin.nameIn(language), skin.warnings.join('\n')),
            for (final MapEntry(key: path, value: error) in library.errors.entries) (path, error),
          ];
          final schemes = SkinLibrary.colorSchemeIds.toSet();
          return ListView(padding: const EdgeInsets.only(bottom: 40), children: [
            // Skins with both sides take light or dark from here.
            ...themeModeTiles(context, controller),
            // The accent color of the standard look and of skins that leave
            // colors to the app; a color scheme sets its own.
            NormalItem(
              title: tr('App theme'),
              subtitle: switch (paletteForSkin(appearance.skin)) {
                final palette? => tr('Set by the {0} color scheme', [palette.name]),
                null => tr('Current: {0} · {1}', [appearance.accentLabel, schemeVariantNames[appearance.schemeVariant]]),
              },
              leading: Icon(AppIcons.eyedropper),
              trailing: CircleAvatar(radius: 12, backgroundColor: controller.accentColor),
              onTap: () => openColorSelect(context, controller),
            ),
            if (context.skin?.glass ?? false)
              ListTile(
                leading: Icon(AppIcons.drop),
                title: Text(tr('Glass')),
                subtitle: Slider(
                  value: appearance.glassOpacity.clamp(SkinGlass.min, 1),
                  min: SkinGlass.min,
                  label: tr('{0}% solid', [(appearance.glassOpacity * 100).round()]),
                  onChanged: (v) => controller.saveAppearance(controller.appearance.copyWith(glassOpacity: v)),
                ),
              ),
            if (context.skin != null)
              SwitchItem(
                title: tr('Skin background'),
                subtitle: tr("The skin's pictures and landscape behind the pages; off leaves a plain color"),
                leading: Icon(AppIcons.image),
                value: appearance.skinBackground,
                onChanged: (v) => controller.saveAppearance(controller.appearance.copyWith(skinBackground: v)),
              ),
            _header(context, tr('Color schemes')),
            grid([for (final s in library.builtIn) if (schemes.contains(s.id)) s], standard: true),
            _tip(context, tr('These follow light and dark mode and keep Lumtub\'s own shapes; the colors change, and the title bar and menu bar take the same colors.')),
            _header(context, tr('Built-in skins')),
            grid([for (final s in library.builtIn) if (!schemes.contains(s.id)) s]),
            _tip(context, tr('A skin changes the colors, shapes, window frame and decorations. Warm light and Low resource mode still work: warm light tints skins too, and Low resource mode leaves out their decorations.')),
            if (library.user.isNotEmpty) ...[
              _header(context, tr('Your skins')),
              grid(library.user),
            ],
            _header(context, tr('Make your own')),
            // Phones, tablets and TVs have no folder to open or editor to
            // write a skin in.
            if (_desktop) NormalItem(
              title: tr('New skin'),
              subtitle: tr('Copies the commented template into your skins folder and opens it'),
              leading: Icon(AppIcons.plus),
              onTap: () => unawaited(_newSkin(context)),
            ),
            if (_desktop) NormalItem(
              title: tr('Open skins folder'),
              subtitle: library.folder?.path ?? '',
              leading: Icon(AppIcons.folderOpen),
              onTap: library.folder == null ? null : () => unawaited(openInExplorer(library.folder!.path)),
            ),
            if (!_desktop) NormalItem(
              title: tr('Add a skin from a file'),
              subtitle: tr('A skin.jsonc, or a zip of a skin\'s folder'),
              leading: Icon(AppIcons.plus),
              onTap: () => unawaited(_importSkin(context)),
            ),
            NormalItem(
              title: tr('Reload skins'),
              subtitle: tr('Saved changes show by themselves; this is for folders that cannot be watched'),
              leading: Icon(AppIcons.arrowClockwise),
              onTap: () => unawaited(library.reload()),
            ),
            NormalItem(
              title: tr('How to make a skin'),
              subtitle: tr('The guide, the format and the pitfalls to avoid'),
              leading: Icon(AppIcons.question),
              onTap: () => unawaited(openExternal(_guide)),
            ),
            if (WindowFrame.supported)
              SwitchItem(
                title: tr('Use the system title bar'),
                subtitle: tr('Keep the usual window frame instead of the title bar and menu bar a skin draws'),
                leading: Icon(AppIcons.browsers),
                value: appearance.systemTitleBar,
                onChanged: (v) => controller.saveAppearance(controller.appearance.copyWith(systemTitleBar: v)),
              ),
            if (WindowFrame.supported && !appearance.systemTitleBar)
              SwitchItem(
                title: tr('Hide the title bar'),
                subtitle: tr('The window buttons move into the menu bar. Only for skins with a menu bar'),
                leading: Icon(AppIcons.rows),
                value: appearance.hideTitleBar,
                onChanged: (v) => controller.saveAppearance(controller.appearance.copyWith(hideTitleBar: v)),
              ),
            if (problems.isNotEmpty) ...[
              _header(context, tr('Problems found')),
              for (final (name, text) in problems)
                ListTile(
                  leading: Icon(AppIcons.warning, color: context.colors.error),
                  title: Text(name),
                  subtitle: SelectableText(text, style: TextStyle(fontSize: 12, color: context.colors.outline)),
                ),
            ],
          ]);
        },
      ),
    );
  }
}

Future<void> _importSkin(BuildContext context) async {
  final file = await openFile(acceptedTypeGroups: const [XTypeGroup(label: 'Skin', extensions: ['zip', 'jsonc', 'json'])]);
  if (file == null || !context.mounted) return;
  try {
    final id = await SkinLibrary.instance.importFile(file.path);
    if (!context.mounted) return;
    final skin = SkinLibrary.instance.byId(id);
    _say(context, tr('Added {0}', [skin?.nameIn(currentLanguage.tag) ?? id]));
  } catch (e) {
    if (context.mounted) _say(context, tr('This is not a skin: {0}', [e is FormatException ? e.message : '$e']));
  }
}

void _say(BuildContext context, String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

Widget _header(BuildContext context, String text) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(text, style: Theme.of(context).textTheme.titleSmall!.copyWith(color: context.colors.primary)),
    );

Widget _tip(BuildContext context, String text) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(AppIcons.info, size: 16, color: context.colors.outline),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: TextStyle(color: context.colors.outline, fontSize: 12, height: 1.5))),
      ]),
    );

/// A skin drawn as a tiny window: its background, title bar, a card and a
/// button, with its name under it. [skin] null is Lumtub's own look.
class SkinCard extends StatelessWidget {
  const SkinCard({super.key, required this.skin, required this.name, this.note, required this.selected, required this.onTap});
  final Skin? skin;
  final String name;
  final String? note;
  final bool selected;
  final VoidCallback onTap;

  Widget _preview(BuildContext context) {
    final skin = this.skin;
    if (skin != null && skin.followsThemeMode) {
      return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(child: ClipRect(child: _drawn(context, skin.forBrightness(Brightness.light)))),
        Expanded(child: ClipRect(child: _drawn(context, skin.forBrightness(Brightness.dark)))),
      ]);
    }
    return _drawn(context, skin);
  }

  Widget _drawn(BuildContext context, Skin? skin) {
    if (skin == null) {
      // Lumtub's own neutral look, whatever is chosen now.
      const colors = ColorScheme.light(surface: Colors.white, onSurface: Color(0xFF18181B), surfaceContainer: Color(0xFFF4F4F5));
      return ColoredBox(
        color: colors.surface,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(height: 6, width: 40, decoration: BoxDecoration(color: colors.onSurface.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 8),
            Expanded(child: Container(decoration: BoxDecoration(color: colors.surfaceContainer, borderRadius: BorderRadius.circular(4)))),
            const SizedBox(height: 8),
            Container(height: 12, width: 34, decoration: BoxDecoration(color: colors.onSurface, borderRadius: BorderRadius.circular(4))),
          ]),
        ),
      );
    }
    final bar = skin.titleBar;
    final radius = (skin.shape.controlRadius ?? 6).clamp(0, 6).toDouble();
    Widget box(SkinSurface? surface, Color fallback, {double r = 0, Widget? child, double? height, double? width}) => Container(
          height: height,
          width: width,
          decoration: surface == null ? BoxDecoration(color: fallback, borderRadius: BorderRadius.circular(r)) : SurfaceDecoration(surface, radius: r),
          child: child,
        );
    return Stack(fit: StackFit.expand, children: [
      ColoredBox(color: skin.colors.page),
      SkinLayers(skin.background),
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (skin.menuBar case final menu? when menu.top)
          box(menu.surface, skin.colors.page, height: 9, child: Row(children: [
            for (var i = 0; i < 3; i++) Padding(padding: const EdgeInsets.only(left: 5), child: Container(width: 12, height: 2, color: menu.text)),
          ])),
        box(bar?.surface ?? skin.topBar, skin.colors.chrome ?? Color.lerp(skin.colors.page, skin.colors.text, 0.08)!, height: 14, child: Row(children: [
          const SizedBox(width: 5),
          Container(width: 22, height: 3, color: bar?.text ?? skin.colors.text),
          const Spacer(),
          for (var i = 0; i < 3; i++) Padding(padding: const EdgeInsets.only(right: 3), child: Container(width: 6, height: 6, decoration: BoxDecoration(border: Border.all(color: bar?.buttonIcon ?? skin.colors.text, width: 1)))),
        ])),
        if (skin.menuBar case final menu? when !menu.top)
          box(menu.surface, skin.colors.page, height: 9, child: Row(children: [
            for (var i = 0; i < 3; i++) Padding(padding: const EdgeInsets.only(left: 5), child: Container(width: 12, height: 2, color: menu.text)),
          ])),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(
                child: box(skin.videoCard, skin.colors.card ?? skin.colors.page, r: (skin.shape.cardRadius ?? 8).clamp(0, 8).toDouble(), child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: Container(decoration: BoxDecoration(color: skin.colors.text.withValues(alpha: 0.18), borderRadius: BorderRadius.circular((skin.shape.thumbnailRadius ?? 4).clamp(0, 4).toDouble())))),
                    const SizedBox(height: 4),
                    Container(height: 3, width: 40, color: skin.colors.text),
                  ]),
                )),
              ),
              const SizedBox(width: 8),
              Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                box(skin.button, skin.colors.page, r: radius, height: 12, width: 34),
                const SizedBox(height: 4),
                box(skin.primaryButton, skin.colors.accent, r: radius, height: 12, width: 34),
              ]),
            ]),
          ),
        ),
      ]),
    ]);
  }

  @override
  Widget build(BuildContext context) => _Lift(builder: (context, hovered, focused) => _card(context, hovered, focused));

  Widget _card(BuildContext context, bool hovered, bool focused) {
    final colors = context.colors;
    final lit = hovered || focused;
    return Semantics(
      button: true,
      selected: selected,
      label: name,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        onHover: _Lift.hoverOf(context),
        onFocusChange: _Lift.focusOf(context),
        child: SizedBox(
          width: 168,
          child: Column(children: [
            AnimatedScale(
              // Under the pointer or the remote's focus the preview comes
              // forward a little.
              scale: focused ? 1.06 : hovered ? 1.03 : 1,
              duration: Motion.of(const Duration(milliseconds: 140)),
              curve: Curves.easeOut,
              child: AnimatedContainer(
                duration: Motion.of(const Duration(milliseconds: 140)),
                height: 104,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: selected || focused ? colors.primary : hovered ? colors.onSurfaceVariant : colors.outlineVariant,
                    width: focused ? 3.5 : selected ? 2.5 : hovered ? 1.5 : 1,
                  ),
                  boxShadow: lit ? [BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 12, offset: const Offset(0, 4))] : null,
                ),
                clipBehavior: Clip.antiAlias,
                child: _preview(context),
              ),
            ),
            const SizedBox(height: 4),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              if (selected) ...[Icon(AppIcons.checkCircleFill, size: 14, color: colors.primary), const SizedBox(width: 4)],
              Flexible(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: selected ? colors.primary : colors.onSurfaceVariant, fontWeight: selected ? FontWeight.w600 : null))),
            ]),
            if (skin case final skin?)
              Text(
                skin.followsThemeMode ? tr('Light and dark') : skin.brightness == Brightness.dark ? tr('Dark only') : tr('Light only'),
                style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: colors.onSurfaceVariant),
              ),
            if (note case final note? when note.isNotEmpty)
              Tooltip(message: note, child: Text(note, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: colors.outline))),
          ]),
        ),
      ),
    );
  }
}

/// Keeps whether its child is under the pointer or has the focus, for the
/// small lift of a card.
class _Lift extends StatefulWidget {
  const _Lift({required this.builder});
  final Widget Function(BuildContext context, bool hovered, bool focused) builder;

  static ValueChanged<bool> hoverOf(BuildContext context) => context.findAncestorStateOfType<_LiftState>()!._hover;
  static ValueChanged<bool> focusOf(BuildContext context) => context.findAncestorStateOfType<_LiftState>()!._focus;

  @override
  State<_Lift> createState() => _LiftState();
}

class _LiftState extends State<_Lift> {
  bool _hovered = false;
  bool _focused = false;

  void _hover(bool v) {
    if (v != _hovered) setState(() => _hovered = v);
  }

  void _focus(bool v) {
    if (v != _focused) setState(() => _focused = v);
  }

  @override
  Widget build(BuildContext context) => Builder(builder: (context) => widget.builder(context, _hovered, _focused));
}
