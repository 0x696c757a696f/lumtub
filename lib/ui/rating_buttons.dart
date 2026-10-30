import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import 'theme.dart';
import 'app_icons.dart';

/// Like and dislike under a comment or a post. With [onRate] the buttons
/// press (signed in, from a page that carried their actions); without it
/// only the like count shows.
class RatingButtons extends StatelessWidget {
  const RatingButtons({super.key, required this.likes, this.state = '', this.loaded = '', this.onRate});

  /// YouTube's own count, such as "1.2万".
  final String likes;

  /// `like`, `dislike` or empty.
  final String state;

  /// [state] when [likes] was counted.
  final String loaded;
  final Future<String?> Function(String want)? onRate;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final small = TextStyle(color: colors.outline, fontSize: 12);
    final count = Text(countLikes(likes, from: loaded, to: state), style: small);
    final onRate = this.onRate;
    if (onRate == null) {
      return Tooltip(
        message: tr('点赞数。在设置 › YouTube 账号里登录后可以点赞和点踩：视频评论用电视码登录，帖子用浏览器登录'),
        child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(AppIcons.thumbsUp, size: 14, color: colors.outline), const SizedBox(width: 4), count]),
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
      button('like', AppIcons.thumbsUp, AppIcons.thumbsUpFill, state == 'like' ? tr('取消点赞') : tr('点赞')),
      count,
      button('dislike', AppIcons.thumbsDown, AppIcons.thumbsDownFill, state == 'dislike' ? tr('取消点踩') : tr('点踩')),
    ]);
  }
}

/// YouTube's like count [likes], counted while the rating was [from], as it
/// is now that it is [to]. A rounded count such as "1.2万" stays as it is:
/// one like does not change it.
String countLikes(String likes, {String from = '', String to = ''}) {
  final change = (to == 'like' ? 1 : 0) - (from == 'like' ? 1 : 0);
  final plain = likes.trim().replaceAll(',', '');
  if (plain.isEmpty) return '${change < 0 ? 0 : change}';
  final number = int.tryParse(plain);
  if (number == null || change == 0) return likes;
  return '${number + change < 0 ? 0 : number + change}';
}
