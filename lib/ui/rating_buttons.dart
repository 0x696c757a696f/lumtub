import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import 'theme.dart';

/// Like and dislike under a comment or a post. With [onRate] the buttons
/// press (signed in, from a page that carried their actions); without it
/// only the like count shows.
class RatingButtons extends StatelessWidget {
  const RatingButtons({super.key, required this.likes, this.state = '', this.onRate});

  /// YouTube's own count, such as "1.2万".
  final String likes;
  /// `like`, `dislike` or empty.
  final String state;
  final Future<String?> Function(String want)? onRate;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final small = TextStyle(color: colors.outline, fontSize: 12);
    final count = Text(likes.isEmpty ? '0' : likes, style: small);
    final onRate = this.onRate;
    if (onRate == null) {
      return Tooltip(
        message: tr('点赞数。在设置 › Google 账号里用电视码登录后可以点赞和点踩'),
        child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.thumb_up_outlined, size: 14, color: colors.outline), const SizedBox(width: 4), count]),
      );
    }
    Future<void> press(String want) async {
      final failed = await onRate(want);
      if (failed != null && context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(failed)));
    }

    Widget button(String want, IconData off, IconData on, String tip) => IconButton(
          tooltip: tip,
          visualDensity: VisualDensity.compact,
          iconSize: 16,
          isSelected: state == want,
          color: colors.outline,
          selectedIcon: Icon(on, color: colors.primary),
          icon: Icon(off),
          onPressed: () => press(want),
        );
    return Row(mainAxisSize: MainAxisSize.min, children: [
      button('like', Icons.thumb_up_outlined, Icons.thumb_up_rounded, state == 'like' ? tr('取消点赞') : tr('点赞')),
      count,
      button('dislike', Icons.thumb_down_outlined, Icons.thumb_down_rounded, state == 'dislike' ? tr('取消点踩') : tr('点踩')),
    ]);
  }
}
