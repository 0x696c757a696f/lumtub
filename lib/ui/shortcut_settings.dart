import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/app_controller.dart';
import '../l10n/l10n.dart';
import '../shortcut_bindings.dart';
import 'app_icons.dart';
import 'player_shortcuts.dart';

/// The list of player actions with their keys: a key can be added, taken
/// off, or moved over from another action.
Future<void> showShortcutSettings(BuildContext context, AppController controller) =>
    showDialog<void>(context: context, builder: (context) => _ShortcutSettings(controller: controller));

class _ShortcutSettings extends StatefulWidget {
  const _ShortcutSettings({required this.controller});
  final AppController controller;

  @override
  State<_ShortcutSettings> createState() => _ShortcutSettingsState();
}

class _ShortcutSettingsState extends State<_ShortcutSettings> {
  String? _note;

  AppController get _controller => widget.controller;

  void _save(Map<String, List<String>> keys, [String? note]) {
    setState(() => _note = note);
    unawaited(_controller.savePreferences(_controller.preferences.copyWith(shortcutKeys: keys)));
  }

  Future<void> _add(PlayerAction action) async {
    final combo = await showDialog<KeyCombo>(context: context, builder: (context) => const _KeyCapture());
    if (combo == null || !mounted) return;
    final prefs = _controller.preferences;
    final now = shortcutKeys(prefs.shortcutKeys);
    if (now[action]!.contains(combo)) return;
    final from = actionOfKey(now, combo, page: action.page);
    _save(
      withShortcutKeys(prefs.shortcutKeys, action, [...now[action]!, combo]),
      from == null ? null : tr('{0} was taken from "{1}"', [combo.label, shortcutActionLabel(from, prefs)]),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          final prefs = _controller.preferences;
          final keys = shortcutKeys(prefs.shortcutKeys);
          final defaults = defaultShortcutKeys();
          final colors = Theme.of(context).colorScheme;
          return AlertDialog(
            scrollable: true,
            title: Text(tr('Customize shortcuts')),
            content: SizedBox(
              width: 520,
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(tr('0-9 and the media keys stay as they are.'), style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12)),
                if (_note != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_note!, style: TextStyle(color: colors.primary, fontSize: 12))),
                const SizedBox(height: 8),
                for (final page in [false, true]) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 12, bottom: 4),
                    child: Text(page ? tr('Every page') : tr('Player'), style: Theme.of(context).textTheme.titleSmall),
                  ),
                  for (final action in PlayerAction.values.where((a) => a.page == page))
                  Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(children: [
                        Expanded(child: Text(shortcutActionLabel(action, prefs))),
                        Flexible(child: Wrap(spacing: 4, runSpacing: 4, alignment: WrapAlignment.end, children: [
                          for (final combo in keys[action]!)
                            InputChip(
                              label: Text(combo.label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                              visualDensity: VisualDensity.compact,
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              deleteButtonTooltipMessage: tr('Remove'),
                              onDeleted: () => _save(withShortcutKeys(prefs.shortcutKeys, action, [for (final k in keys[action]!) if (k != combo) k])),
                            ),
                        ])),
                        IconButton(tooltip: tr('Add a key'), visualDensity: VisualDensity.compact, icon: Icon(AppIcons.plus, size: 16), onPressed: () => _add(action)),
                        IconButton(
                          tooltip: tr('Reset'),
                          visualDensity: VisualDensity.compact,
                          icon: Icon(AppIcons.arrowCounterClockwise, size: 16),
                          onPressed: _same(keys[action]!, defaults[action]!) ? null : () => _save(resetShortcutKeys(prefs.shortcutKeys, action)),
                        ),
                      ]),
                    ),
                ],
              ]),
            ),
            actions: [
              TextButton(onPressed: prefs.shortcutKeys.isEmpty ? null : () => _save(const {}), child: Text(tr('Reset all'))),
              FilledButton(onPressed: () => Navigator.pop(context), child: Text(tr('Done'))),
            ],
          );
        },
      );
}

bool _same(List<KeyCombo> a, List<KeyCombo> b) => a.length == b.length && a.every(b.contains);

/// Waits for one key, with any modifiers held; the next key pressed is
/// the answer, Esc included.
class _KeyCapture extends StatefulWidget {
  const _KeyCapture();

  @override
  State<_KeyCapture> createState() => _KeyCaptureState();
}

class _KeyCaptureState extends State<_KeyCapture> {
  bool _fixed = false;

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.handled;
    final combo = KeyCombo.of(event, HardwareKeyboard.instance);
    if (combo == null) return KeyEventResult.handled;
    if (fixedKey(combo)) {
      setState(() => _fixed = true);
    } else {
      Navigator.pop(context, combo);
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) => Focus(
        autofocus: true,
        onKeyEvent: _onKey,
        child: AlertDialog(
          title: Text(tr('Press a key')),
          content: Text(_fixed ? tr('0-9 and the media keys stay as they are; press another key.') : tr('Press the key or key combination to use.')),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Cancel')))],
        ),
      );
}
