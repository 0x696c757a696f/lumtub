import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_controller.dart';
import '../../l10n/l10n.dart';
import '../../skins/skin.dart';
import '../../skins/skin_library.dart';
import '../../window_frame.dart';
import '../app_icons.dart';
import '../common.dart';
import '../skin_paint.dart';
import '../theme.dart';
import '../../widgets/pilinara_settings_tiles.dart';
import 'downloads_page.dart' show openInExplorer;

const _guide = 'https://github.com/0x696c757a696f/lumtub/blob/main/skins/README.md';

/// Settings › Appearance › Skins: the built-in skins, the user's own, and
/// the tools for making one.
Future<void> openSkins(BuildContext context, AppController controller) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => _SkinsPage(controller: controller)));

class _SkinsPage extends StatelessWidget {
  const _SkinsPage({required this.controller});
  final AppController controller;

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
      appBar: AppBar(title: Text(tr('Skins'))),
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
          return ListView(padding: const EdgeInsets.only(bottom: 40), children: [
            _header(context, tr('Color schemes')),
            grid([for (final s in library.builtIn) if (s.followsThemeMode) s], standard: true),
            _tip(context, tr('These follow light and dark mode and keep Lumtub\'s own shapes; only the colours change.')),
            _header(context, tr('Built-in skins')),
            grid([for (final s in library.builtIn) if (!s.followsThemeMode) s]),
            _tip(context, tr('A skin changes the colours, shapes, window frame and decorations. Warm light and Low resource mode still work: warm light tints skins too, and Low resource mode leaves out their decorations.')),
            if (library.user.isNotEmpty) ...[
              _header(context, tr('Your skins')),
              grid(library.user),
            ],
            _header(context, tr('Make your own')),
            NormalItem(
              title: tr('New skin'),
              subtitle: tr('Copies the commented template into your skins folder and opens it'),
              leading: const Icon(AppIcons.plus),
              onTap: () => unawaited(_newSkin(context)),
            ),
            NormalItem(
              title: tr('Open skins folder'),
              subtitle: library.folder?.path ?? '',
              leading: const Icon(AppIcons.folderOpen),
              onTap: library.folder == null ? null : () => unawaited(openInExplorer(library.folder!.path)),
            ),
            NormalItem(
              title: tr('Reload skins'),
              subtitle: tr('Saved changes show by themselves; this is for folders that cannot be watched'),
              leading: const Icon(AppIcons.arrowClockwise),
              onTap: () => unawaited(library.reload()),
            ),
            NormalItem(
              title: tr('How to make a skin'),
              subtitle: tr('The guide, the format and the pitfalls to avoid'),
              leading: const Icon(AppIcons.question),
              onTap: () => unawaited(openExternal(_guide)),
            ),
            if (WindowFrame.supported)
              SwitchItem(
                title: tr('Use the system title bar'),
                subtitle: tr('Keep the usual window frame instead of the one a skin draws'),
                leading: const Icon(AppIcons.browsers),
                value: appearance.systemTitleBar,
                onChanged: (v) => controller.saveAppearance(controller.appearance.copyWith(systemTitleBar: v)),
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
        box(bar?.surface ?? skin.topBar, skin.colors.chrome ?? Color.lerp(skin.colors.page, skin.colors.text, 0.08)!, height: 14, child: Row(children: [
          const SizedBox(width: 5),
          Container(width: 22, height: 3, color: bar?.text ?? skin.colors.text),
          const Spacer(),
          for (var i = 0; i < 3; i++) Padding(padding: const EdgeInsets.only(right: 3), child: Container(width: 6, height: 6, decoration: BoxDecoration(border: Border.all(color: bar?.buttonIcon ?? skin.colors.text, width: 1)))),
        ])),
        if (skin.menuBar case final menu?)
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
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      button: true,
      selected: selected,
      label: name,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: SizedBox(
          width: 168,
          child: Column(children: [
            Container(
              height: 104,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: selected ? colors.primary : colors.outlineVariant, width: selected ? 2.5 : 1),
              ),
              clipBehavior: Clip.antiAlias,
              child: _preview(context),
            ),
            const SizedBox(height: 4),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              if (selected) ...[Icon(AppIcons.checkCircleFill, size: 14, color: colors.primary), const SizedBox(width: 4)],
              Flexible(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: selected ? colors.primary : colors.onSurfaceVariant, fontWeight: selected ? FontWeight.w600 : null))),
            ]),
            if (note case final note? when note.isNotEmpty)
              Tooltip(message: note, child: Text(note, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: colors.outline))),
          ]),
        ),
      ),
    );
  }
}
