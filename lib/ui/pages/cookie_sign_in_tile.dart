import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../youtube_web_sign_in.dart';
import '../common.dart';
import '../theme.dart';
import '../../l10n/l10n.dart';

/// The cookie sign-in, for liking posts, voting in polls and writing under
/// posts: signing in in a browser window of its own, or importing a
/// cookies.txt.
class CookieSignInTile extends StatefulWidget {
  const CookieSignInTile(this.sign, {super.key, required this.note});
  final YoutubeWebSignIn sign;
  final TextStyle note;

  @override
  State<CookieSignInTile> createState() => _CookieSignInTileState();
}

class _CookieSignInTileState extends State<CookieSignInTile> {
  /// Whether the cookies are kept behind the user's confirmation.
  bool _presence = true;

  /// What confirms it here, where the system has it.
  static String? get _presenceName => Platform.isWindows
      ? 'Windows Hello'
      : Platform.isMacOS
          ? tr('Touch ID 或密码')
          : null;

  static String _guard(CookieGuard? guard) => switch (guard) {
        CookieGuard.presence => tr('用 {0} 保护：每次打开 Lumtub 后第一次用到时验证一次', [_presenceName ?? tr('系统验证')]),
        CookieGuard.hardware => tr('用这台电脑的 TPM 芯片加密，拷到别处解不开'),
        CookieGuard.keyring => tr('用系统钥匙串加密保存'),
        CookieGuard.account => tr('用 Windows 账号加密保存（这台电脑没有可用的 TPM）'),
        CookieGuard.file => tr('只靠文件权限保护（这台设备没有可用的系统钥匙串）'),
        null => tr('已加密保存'),
      };

  Future<void> _import() async {
    final file = await openFile(acceptedTypeGroups: [
      XTypeGroup(label: tr('Cookie 文件'), extensions: const ['txt'])
    ]);
    if (file == null || !mounted) return;
    var delete = true;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(tr('导入 cookies.txt？')),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('只取 youtube.com 的 Cookie，加密后保存在本机。')),
            const SizedBox(height: 8),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: delete,
              onChanged: (value) => setState(() => delete = value ?? true),
              title: Text(tr('导入后清除并删除这个文件（推荐）')),
              subtitle: Text(tr('留在磁盘上的 cookies.txt 是明文，谁拿到都能登录你的账号。')),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('取消'))),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(tr('导入'))),
          ],
        ),
      ),
    );
    if (confirmed == true) widget.sign.importFile(file.path, presence: _presence, delete: delete);
  }

  @override
  Widget build(BuildContext context) {
    final sign = widget.sign;
    final colors = context.colors;
    final error = sign.error;
    final presence = _presenceName;
    return ListenableBuilder(
      listenable: sign,
      builder: (context, _) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (sign.waiting)
          ListTile(
            leading: const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5)),
            title: Text(sign.reading
                ? tr('正在读取登录…')
                : sign.browser == null
                    ? tr('正在打开浏览器…')
                    : tr('请在 {0} 窗口里登录 YouTube', [sign.browser!])),
            subtitle: Text(tr('看到 YouTube 首页后关闭这个浏览器窗口，Lumtub 会自动读取登录。这是一个临时的独立窗口，不会碰你平时浏览器里的数据。')),
            isThreeLine: true,
            trailing: sign.browser == null || sign.reading ? null : TextButton(onPressed: sign.cancel, child: Text(tr('取消'))),
          )
        else if (sign.signedIn)
          ListTile(
            leading: Icon(Icons.lock_rounded, color: colors.primary),
            title: Text(tr('已用浏览器登录')),
            subtitle: Text('${tr('可以给社区帖子点赞、投票和评论')}\n${_guard(sign.guard)}'),
            isThreeLine: true,
            trailing: OutlinedButton(onPressed: sign.signOut, child: Text(tr('退出'))),
          )
        else ...[
          ListTile(
            leading: Icon(Icons.public_rounded, color: colors.primary),
            title: Text(tr('未登录')),
            subtitle: Text(tr('在一个临时的浏览器窗口里登录。Lumtub 只取 youtube.com 的 Cookie，加密保存后删除这个窗口的全部数据。')),
            trailing: FilledButton.tonal(onPressed: () => sign.signInWithBrowser(presence: _presence), child: Text(tr('用浏览器登录'))),
          ),
          if (presence != null)
            SwitchListTile(
              value: _presence,
              onChanged: (value) => setState(() => _presence = value),
              title: Text(tr('用 {0} 保护', [presence])),
              subtitle: Text(tr('每次打开 Lumtub 后第一次用到登录时验证一次。电脑上的其他程序没法悄悄解开 Cookie。')),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: _import, icon: const Icon(Icons.file_open_outlined, size: 18), label: Text(tr('改为导入 cookies.txt')))),
          ),
        ],
        if (error != null) Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 8), child: ErrorBanner(error)),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 8),
          child: Text(
            tr('Cookie 等于这个账号的登录状态，建议用一个小号。Cookie 只留在 Lumtub 的原生核心里，界面和日志都拿不到，只发给 youtube.com。在 Google 账号里退出所有设备后它会失效。'),
            style: widget.note,
          ),
        ),
      ]),
    );
  }
}
