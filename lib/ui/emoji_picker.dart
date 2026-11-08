import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../live_chat_composer.dart';
import 'app_icons.dart';
import 'theme.dart';

/// The emoji offered, by group: the ones people use most in comments and
/// chats, drawn by the system's emoji font.
const emojiGroups = <(String, String)>[
  ('Smileys', '😀😃😄😁😆😅🤣😂🙂🙃😉😊😇🥰😍🤩😘😗😚😙😋😛😜🤪😝🤑🤗🤭🤫🤔🤐🤨😐😑😶😏😒🙄😬😮‍💨🤥😌😔😪🤤😴😷🤒🤕🤢🤮🥵🥶🥴😵🤯🤠🥳😎🤓🧐😕😟🙁😮😯😲😳🥺😦😧😨😰😥😢😭😱😖😣😞😓😩😫🥱😤😡😠🤬😈👿💀💩🤡👻👽🤖'),
  ('Gestures', '👋🤚🖐✋🖖👌🤌🤏✌🤞🤟🤘🤙👈👉👆👇☝👍👎✊👊🤛🤜👏🙌👐🤲🤝🙏✍💪🦾👀👁👂🧠'),
  ('Hearts', '❤🧡💛💚💙💜🖤🤍🤎💔❣💕💞💓💗💖💘💝💟💯💢💥💫💦💨🕳💬💭💤✨⭐🌟🔥⚡🎉🎊'),
  ('Nature', '🐶🐱🐭🐹🐰🦊🐻🐼🐨🐯🦁🐮🐷🐸🐵🙈🙉🙊🐔🐧🐦🐤🦆🦅🦉🐺🐴🦄🐝🦋🐌🐞🐢🐍🐙🐬🐳🐟🌸🌹🌻🌷🌱🌲🍀🍁🌈☀🌙☁❄🌊'),
  ('Food', '🍎🍊🍋🍌🍉🍇🍓🍒🍑🥭🍍🥥🥝🍅🥑🌶🌽🥕🍞🧀🍳🍔🍟🍕🌭🌮🍜🍣🍱🥟🍚🍙🍰🎂🍩🍪🍫🍬🍭🍿☕🍵🧋🍺🍻🍷🥂'),
  ('Activities', '⚽🏀🏈⚾🎾🏐🎱🏓🎮🕹🎲🎯🎳🎸🎹🎺🎻🥁🎤🎧🎬🎨📷📺📱💻⌨🎁🏆🥇🥈🥉🚗✈🚀⏰💡📌📎✅❌❓❗⚠➕➖🆗🆒🆕'),
];

/// Splits [group] into its emoji, keeping joined ones (`😮‍💨`) whole.
List<String> emojiOf(String group) {
  final out = <String>[];
  final runes = group.runes.toList();
  for (var i = 0; i < runes.length; i++) {
    var emoji = String.fromCharCode(runes[i]);
    while (i + 2 < runes.length && runes[i + 1] == 0x200D) {
      emoji += String.fromCharCodes([runes[i + 1], runes[i + 2]]);
      i += 2;
    }
    while (i + 1 < runes.length && runes[i + 1] == 0xFE0F) {
      emoji += String.fromCharCode(runes[++i]);
    }
    // Older symbols (❤ ☀ ✈) draw as plain text without the emoji form.
    if (runes[i] < 0x1F000 && !emoji.contains('\u{FE0F}') && !emoji.contains('\u{200D}')) emoji += '\u{FE0F}';
    out.add(emoji);
  }
  return out;
}

/// Puts [text] in [field] where its cursor is, over what is selected.
void insertAtCursor(TextEditingController field, String text) {
  final value = field.value;
  final selection = value.selection.isValid ? value.selection : TextSelection.collapsed(offset: value.text.length);
  field.value = TextEditingValue(
    text: value.text.replaceRange(selection.start, selection.end, text),
    selection: TextSelection.collapsed(offset: selection.start + text.length),
  );
}

/// A button opening the emoji, with the channel's own first when a live
/// chat offers them; a picked one goes into [field] where its cursor is.
class EmojiButton extends StatelessWidget {
  const EmojiButton({super.key, required this.field, this.focus, this.channel = const [], this.size = 18});
  final TextEditingController field;
  final FocusNode? focus;
  final List<ChannelEmoji> channel;
  final double size;

  @override
  Widget build(BuildContext context) => MenuAnchor(
        menuChildren: [_EmojiGrid(field: field, focus: focus, channel: channel)],
        builder: (context, menu, _) => IconButton(
          tooltip: tr('Emoji'),
          icon: Icon(AppIcons.smiley, size: size),
          onPressed: () => menu.isOpen ? menu.close() : menu.open(),
        ),
      );
}

class _EmojiGrid extends StatelessWidget {
  const _EmojiGrid({required this.field, this.focus, required this.channel});
  final TextEditingController field;
  final FocusNode? focus;
  final List<ChannelEmoji> channel;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    Widget heading(String name) => Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
          child: Text(name, style: context.text.labelSmall?.copyWith(color: colors.onSurfaceVariant)),
        );
    Widget cell({required String tooltip, required Widget child, VoidCallback? onTap}) => Tooltip(
          message: tooltip,
          waitDuration: const Duration(milliseconds: 600),
          child: InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: onTap,
            child: SizedBox.square(dimension: 36, child: Center(child: child)),
          ),
        );
    void pick(String text) {
      insertAtCursor(field, text);
      focus?.requestFocus();
    }

    return SizedBox(
      width: 340,
      height: 300,
      child: ListView(primary: false, padding: const EdgeInsets.all(4), children: [
        if (channel.isNotEmpty) ...[
          heading(tr("Channel's emoji")),
          Wrap(children: [
            for (final emoji in channel)
              cell(
                tooltip: emoji.locked ? tr('{0} (for members)', [emoji.shortcut]) : emoji.shortcut,
                onTap: emoji.locked ? null : () => pick(emoji.shortcut),
                child: Opacity(
                  opacity: emoji.locked ? 0.35 : 1,
                  child: Image.network(emoji.url, width: 24, height: 24, errorBuilder: (context, _, __) => Text(emoji.shortcut, style: const TextStyle(fontSize: 9))),
                ),
              ),
          ]),
        ],
        for (final (name, group) in emojiGroups) ...[
          heading(tr(name)),
          Wrap(children: [
            for (final emoji in emojiOf(group)) cell(tooltip: emoji, onTap: () => pick(emoji), child: Text(emoji, style: const TextStyle(fontSize: 20))),
          ]),
        ],
      ]),
    );
  }
}
