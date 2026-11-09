import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show SingleActivator;

/// A player action whose keys can be changed in the settings.
enum PlayerAction {
  playPause,
  seekBack,
  seekForward,
  longSeekBack,
  longSeekForward,
  volumeUp,
  volumeDown,
  mute,
  slower,
  faster,
  fullscreen,
  exitFullscreen,
  previous,
  next,
  frameBack,
  frameForward,
  start,
  end,
  lineBack,
  lineNext,
  lineReplay,
  copySubtitle,
  theater,
  lightsOff,
  screenshot,
  stats;

  static PlayerAction? parse(String name) => values.where((a) => a.name == name).firstOrNull;
}

/// One key with the modifiers held with it, saved as `ctrl+shift+<key id>`.
class KeyCombo {
  const KeyCombo(this.key, {this.control = false, this.shift = false, this.alt = false, this.meta = false});
  final LogicalKeyboardKey key;
  final bool control;
  final bool shift;
  final bool alt;
  final bool meta;

  static KeyCombo? parse(String text) {
    final parts = text.split('+');
    final id = int.tryParse(parts.last);
    if (id == null) return null;
    final key = LogicalKeyboardKey.findKeyByKeyId(id) ?? LogicalKeyboardKey(id);
    final mods = parts.sublist(0, parts.length - 1).toSet();
    return KeyCombo(key, control: mods.contains('ctrl'), shift: mods.contains('shift'), alt: mods.contains('alt'), meta: mods.contains('meta'));
  }

  /// The key pressed in [event] with the modifiers [keyboard] holds; null
  /// for a modifier alone.
  static KeyCombo? of(KeyEvent event, HardwareKeyboard keyboard) {
    if (_modifiers.contains(event.logicalKey)) return null;
    return KeyCombo(
      event.logicalKey,
      control: keyboard.isControlPressed,
      shift: keyboard.isShiftPressed,
      alt: keyboard.isAltPressed,
      meta: keyboard.isMetaPressed,
    );
  }

  SingleActivator get activator => SingleActivator(key, control: control, shift: shift, alt: alt, meta: meta);

  String get id => [if (control) 'ctrl', if (shift) 'shift', if (alt) 'alt', if (meta) 'meta', '${key.keyId}'].join('+');

  /// As written on the key cap: `Ctrl + Shift + K`, `←`, `Space`; ⌘ and ⌥
  /// on a Mac.
  String get label {
    final mac = Platform.isMacOS;
    return [
      if (control) mac ? '⌃' : 'Ctrl',
      if (alt) mac ? '⌥' : 'Alt',
      if (shift) mac ? '⇧' : 'Shift',
      if (meta) mac ? '⌘' : 'Win',
      keyLabel(key),
    ].join(' + ');
  }

  @override
  bool operator ==(Object other) => other is KeyCombo && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => id;
}

/// [key] as a short name.
String keyLabel(LogicalKeyboardKey key) {
  final named = _names[key];
  if (named != null) return named;
  final label = key.keyLabel;
  if (label.trim().isEmpty) return key.debugName ?? '#${key.keyId}';
  return label.length == 1 ? label.toUpperCase() : label;
}

final _names = {
  LogicalKeyboardKey.arrowLeft: '←',
  LogicalKeyboardKey.arrowRight: '→',
  LogicalKeyboardKey.arrowUp: '↑',
  LogicalKeyboardKey.arrowDown: '↓',
  LogicalKeyboardKey.space: 'Space',
  LogicalKeyboardKey.escape: 'Esc',
  LogicalKeyboardKey.pageUp: 'PgUp',
  LogicalKeyboardKey.pageDown: 'PgDn',
};

final _modifiers = {
  LogicalKeyboardKey.control,
  LogicalKeyboardKey.controlLeft,
  LogicalKeyboardKey.controlRight,
  LogicalKeyboardKey.shift,
  LogicalKeyboardKey.shiftLeft,
  LogicalKeyboardKey.shiftRight,
  LogicalKeyboardKey.alt,
  LogicalKeyboardKey.altLeft,
  LogicalKeyboardKey.altRight,
  LogicalKeyboardKey.meta,
  LogicalKeyboardKey.metaLeft,
  LogicalKeyboardKey.metaRight,
  LogicalKeyboardKey.capsLock,
  LogicalKeyboardKey.fn,
};

/// Keys that always do the same thing and cannot be given to an action:
/// 0-9 jump to tenths of the video, the media keys play, pause and skip.
bool fixedKey(KeyCombo combo) =>
    !combo.control && !combo.alt && !combo.meta && !combo.shift && (_digits.contains(combo.key) || _media.contains(combo.key));

final _digits = {
  LogicalKeyboardKey.digit0, LogicalKeyboardKey.digit1, LogicalKeyboardKey.digit2, LogicalKeyboardKey.digit3, LogicalKeyboardKey.digit4,
  LogicalKeyboardKey.digit5, LogicalKeyboardKey.digit6, LogicalKeyboardKey.digit7, LogicalKeyboardKey.digit8, LogicalKeyboardKey.digit9,
  LogicalKeyboardKey.numpad0, LogicalKeyboardKey.numpad1, LogicalKeyboardKey.numpad2, LogicalKeyboardKey.numpad3, LogicalKeyboardKey.numpad4,
  LogicalKeyboardKey.numpad5, LogicalKeyboardKey.numpad6, LogicalKeyboardKey.numpad7, LogicalKeyboardKey.numpad8, LogicalKeyboardKey.numpad9,
};

final _media = {LogicalKeyboardKey.mediaPlayPause, LogicalKeyboardKey.mediaPlay, LogicalKeyboardKey.mediaPause, LogicalKeyboardKey.mediaTrackNext, LogicalKeyboardKey.mediaTrackPrevious};

/// The keys each action has out of the box.
Map<PlayerAction, List<KeyCombo>> defaultShortcutKeys() {
  final mac = Platform.isMacOS;
  // A TV remote's OK button plays and pauses; its up and down arrows move
  // to the controls, as the TV sets the volume itself.
  final android = Platform.isAndroid;
  return {
    PlayerAction.playPause: [const KeyCombo(LogicalKeyboardKey.space), const KeyCombo(LogicalKeyboardKey.keyK), if (android) const KeyCombo(LogicalKeyboardKey.select)],
    PlayerAction.seekBack: const [KeyCombo(LogicalKeyboardKey.arrowLeft)],
    PlayerAction.seekForward: const [KeyCombo(LogicalKeyboardKey.arrowRight)],
    PlayerAction.longSeekBack: const [KeyCombo(LogicalKeyboardKey.keyJ)],
    PlayerAction.longSeekForward: const [KeyCombo(LogicalKeyboardKey.keyL)],
    PlayerAction.volumeUp: [if (!android) const KeyCombo(LogicalKeyboardKey.arrowUp)],
    PlayerAction.volumeDown: [if (!android) const KeyCombo(LogicalKeyboardKey.arrowDown)],
    PlayerAction.mute: const [KeyCombo(LogicalKeyboardKey.keyM)],
    PlayerAction.slower: const [KeyCombo(LogicalKeyboardKey.comma, shift: true)],
    PlayerAction.faster: const [KeyCombo(LogicalKeyboardKey.period, shift: true)],
    PlayerAction.fullscreen: const [KeyCombo(LogicalKeyboardKey.keyF)],
    PlayerAction.exitFullscreen: const [KeyCombo(LogicalKeyboardKey.escape)],
    PlayerAction.previous: const [KeyCombo(LogicalKeyboardKey.keyP, shift: true), KeyCombo(LogicalKeyboardKey.bracketLeft)],
    PlayerAction.next: const [KeyCombo(LogicalKeyboardKey.keyN, shift: true), KeyCombo(LogicalKeyboardKey.bracketRight)],
    PlayerAction.frameBack: const [KeyCombo(LogicalKeyboardKey.comma)],
    PlayerAction.frameForward: const [KeyCombo(LogicalKeyboardKey.period)],
    PlayerAction.start: const [KeyCombo(LogicalKeyboardKey.home)],
    PlayerAction.end: const [KeyCombo(LogicalKeyboardKey.end)],
    PlayerAction.lineBack: const [KeyCombo(LogicalKeyboardKey.keyA)],
    PlayerAction.lineNext: const [KeyCombo(LogicalKeyboardKey.keyD)],
    PlayerAction.lineReplay: const [KeyCombo(LogicalKeyboardKey.keyR)],
    PlayerAction.copySubtitle: [KeyCombo(LogicalKeyboardKey.keyC, control: !mac, meta: mac)],
    PlayerAction.theater: const [KeyCombo(LogicalKeyboardKey.keyT)],
    PlayerAction.lightsOff: const [KeyCombo(LogicalKeyboardKey.keyB)],
    PlayerAction.screenshot: const [KeyCombo(LogicalKeyboardKey.keyS)],
    PlayerAction.stats: const [KeyCombo(LogicalKeyboardKey.keyI)],
  };
}

/// The keys of every action: [saved] where it names one, the default keys
/// otherwise, less any key that a saved action took over.
Map<PlayerAction, List<KeyCombo>> shortcutKeys(Map<String, List<String>> saved) {
  final chosen = <PlayerAction, List<KeyCombo>>{
    for (final MapEntry(:key, :value) in saved.entries)
      if (PlayerAction.parse(key) case final action?) action: [for (final text in value) if (KeyCombo.parse(text) case final combo? when !fixedKey(combo)) combo],
  };
  final taken = {for (final keys in chosen.values) ...keys};
  return {
    for (final MapEntry(:key, :value) in defaultShortcutKeys().entries) key: chosen[key] ?? [for (final combo in value) if (!taken.contains(combo)) combo],
  };
}

/// [saved] with [action] given [keys], which are taken off any other
/// action; actions back at their defaults are left out.
Map<String, List<String>> withShortcutKeys(Map<String, List<String>> saved, PlayerAction action, List<KeyCombo> keys) {
  final now = shortcutKeys(saved);
  now[action] = keys;
  for (final other in now.keys) {
    if (other != action) now[other] = [for (final combo in now[other]!) if (!keys.contains(combo)) combo];
  }
  return _saved(now);
}

/// [saved] with [action] back on its default keys, which leave any other
/// action that took them.
Map<String, List<String>> resetShortcutKeys(Map<String, List<String>> saved, PlayerAction action) =>
    withShortcutKeys(saved, action, defaultShortcutKeys()[action]!);

Map<String, List<String>> _saved(Map<PlayerAction, List<KeyCombo>> keys) {
  final defaults = defaultShortcutKeys();
  bool same(List<KeyCombo> a, List<KeyCombo> b) => a.length == b.length && a.every(b.contains);
  return {
    for (final MapEntry(:key, :value) in keys.entries)
      // An action left with its defaults less those others hold reads back
      // the same without being written out.
      if (!same(value, [for (final combo in defaults[key]!) if (!keys.entries.any((e) => e.key != key && e.value.contains(combo))) combo]))
        key.name: [for (final combo in value) combo.id],
  };
}

/// The action [combo] belongs to in [keys], if any.
PlayerAction? actionOfKey(Map<PlayerAction, List<KeyCombo>> keys, KeyCombo combo) =>
    keys.entries.where((e) => e.value.contains(combo)).firstOrNull?.key;
