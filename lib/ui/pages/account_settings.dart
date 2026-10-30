import 'package:flutter/material.dart';

import '../../app/account_controller.dart';
import '../../google_auth.dart';
import '../../youtube_account.dart';
import '../../youtube_tv_sign_in.dart';
import '../../youtube_web_sign_in.dart';
import '../common.dart';
import '../theme.dart';
import 'cookie_sign_in_tile.dart';
import '../../l10n/l10n.dart';
import '../app_icons.dart';

/// Google sign-in, sync and the OAuth client used for it.
class AccountSettings extends StatelessWidget {
  const AccountSettings({super.key, required this.account, this.tvSignIn, this.webSignIn, this.saveTvSamples, required this.note});
  final AccountController? account;
  final YoutubeTvSignIn? tvSignIn;
  final YoutubeWebSignIn? webSignIn;
  final Future<String> Function()? saveTvSamples;
  final TextStyle note;

  @override
  Widget build(BuildContext context) {
    final account = this.account;
    if (account == null) return ListTile(title: Text(tr('正在准备…')));
    final tv = tvSignIn;
    final web = webSignIn;
    return ListenableBuilder(
      listenable: Listenable.merge([account, if (tv != null) tv, if (web != null) web]),
      builder: (context, _) {
        final colors = context.colors;
        final error = account.error;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const _Intro(),
          _Section(
            number: 1,
            title: tr('Google 登录'),
            purpose: tr('同步订阅和播放列表，给视频点赞、评论、订阅。推荐，大多数人只需要这一个'),
            signedIn: account.signedIn,
            expanded: true,
            children: [
              switch (account.state) {
                AccountState.signedIn => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    ListTile(
                      leading: CircleAvatar(
                        backgroundColor: colors.primaryContainer,
                        child: Icon(AppIcons.userFill, color: colors.onPrimaryContainer),
                      ),
                      title: Text(account.name ?? tr('YouTube 账号')),
                      trailing: account.canWrite ? null : FilledButton.tonal(onPressed: account.signIn, child: Text(tr('重新登录以启用点赞和评论'))),
                      subtitle: Text(account.syncing
                          ? tr('正在同步订阅和播放列表…')
                          : account.lastSync == null
                              ? tr('已登录，尚未同步')
                              : tr('上次同步：{0} {1}', [formatDate(account.lastSync!), _time(account.lastSync!)])),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Wrap(spacing: 8, runSpacing: 8, children: [
                        FilledButton.tonalIcon(
                          onPressed: account.syncing ? null : account.sync,
                          icon: account.syncing ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(AppIcons.arrowsCounterClockwise),
                          label: Text(tr('立即同步')),
                        ),
                        OutlinedButton(onPressed: () => _confirmSignOut(context, account), child: Text(tr('退出登录'))),
                      ]),
                    ),
                  ]),
                AccountState.signingIn => ListTile(
                    leading: const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5)),
                    title: Text(tr('请在浏览器中完成登录')),
                    subtitle: Text(tr('已在默认浏览器打开 Google 登录页，完成后会自动回到这里。')),
                    trailing: TextButton(onPressed: account.cancelSignIn, child: Text(tr('取消'))),
                  ),
                AccountState.signedOut => ListTile(
                    leading: Icon(AppIcons.userCircle, color: colors.primary),
                    title: Text(tr('未登录')),
                    subtitle: Text(account.client == null ? tr('这个版本没有内置 Google 客户端，需要先在下方填写你自己的客户端。') : tr('登录后可以导入订阅、播放列表和喜欢的视频，也可以点赞、评论、保存到播放列表和订阅。')),
                    trailing: FilledButton.icon(
                      onPressed: account.client == null ? null : account.signIn,
                      icon: const Icon(AppIcons.signIn),
                      label: Text(tr('登录')),
                    ),
                  ),
              },
              if (error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: error == YouTubeApiException.apiNotEnabled ? ErrorBanner(error, onRetry: () => openExternal(YouTubeApiException.enableApiUrl), retryLabel: tr('去启用')) : ErrorBanner(error),
                ),
              _ClientSettings(account: account, note: note),
            ],
          ),
          if (tv != null)
            _Section(
              number: 2,
              title: tr('电视码登录'),
              purpose: tr('YouTube 首页推荐、观看历史，给评论点赞'),
              signedIn: tv.signedIn,
              expanded: tv.signedIn || tv.state == TvSignInState.waiting || tv.error != null,
              children: [
                _TvSignInTile(tv, saveSamples: saveTvSamples, note: note),
                if (_differentAccounts(account, tv) case final names?)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: ErrorBanner(tr('两种登录显示的账号不同（Google：{0}，电视码：{1}）。如果不是同一个账号，订阅、点赞会分在两个账号上，建议退出一个重新登录。', [names.$1, names.$2])),
                  ),
              ],
            ),
          if (web != null)
            _Section(
              number: tv == null ? 2 : 3,
              title: tr('浏览器登录'),
              purpose: tr('只用于给社区帖子点赞、投票和评论'),
              signedIn: web.signedIn,
              expanded: web.signedIn || web.waiting || web.error != null,
              children: [CookieSignInTile(web, note: note)],
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Text(
              tr('登录时请用同一个 Google 账号。登录凭据加密保存在本机，只有你在 Lumtub 里点赞、评论、保存或订阅时才会修改账号，不会上传本机的观看记录。视频播放不使用账号，会员或年龄限制视频不一定能播放。'),
              style: note,
            ),
          ),
        ]);
      },
    );
  }

  /// The two names when both sign-ins show one and they differ.
  static (String, String)? _differentAccounts(AccountController account, YoutubeTvSignIn tv) {
    final google = account.signedIn ? account.name?.trim() : null;
    final television = tv.signedIn ? tv.name?.trim() : null;
    if (google == null || television == null || google.isEmpty || television.isEmpty) return null;
    return google.toLowerCase() == television.toLowerCase() ? null : (google, television);
  }

  static String _time(DateTime time) => '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

  Future<void> _confirmSignOut(BuildContext context, AccountController account) async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: Text(tr('退出 Google 账号？')),
              content: Text(tr('会删除本机保存的登录凭据，并通知 Google 撤销 Lumtub 的授权。已经导入的关注频道和播放列表会保留。')),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('取消'))),
                FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(tr('退出登录'))),
              ],
            ));
    if (confirmed == true) await account.signOut();
  }
}

/// What the sign-ins are for, above them.
class _Intro extends StatelessWidget {
  const _Intro();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr('登录都是可选的'), style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(tr('不登录也能搜索和播放。想用哪项功能，就只登录对应的那一个；打勾的是已经登录的。'), style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant)),
        ]),
      );
}

/// A sign-in step's number, ticked once it is done.
class _Badge extends StatelessWidget {
  const _Badge(this.number, {required this.done});
  final int number;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: 24,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(shape: BoxShape.circle, color: done ? colors.primary : colors.surfaceContainerHighest),
      child: done ? Icon(AppIcons.check, size: 16, color: colors.onPrimary) : Text('$number', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colors.onSurfaceVariant)),
    );
  }
}

/// One sign-in: a header with what it is for, folding its controls away
/// until they are wanted.
class _Section extends StatelessWidget {
  const _Section({required this.number, required this.title, required this.purpose, required this.signedIn, required this.expanded, required this.children});
  final int number;
  final String title;
  final String purpose;
  final bool signedIn;
  final bool expanded;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: colors.outlineVariant)),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        key: PageStorageKey('account:$number'),
        initiallyExpanded: expanded,
        shape: const Border(),
        collapsedShape: const Border(),
        leading: _Badge(number, done: signedIn),
        title: Text(title, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
        subtitle: Text(purpose, style: context.text.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
        childrenPadding: const EdgeInsets.only(bottom: 8),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

/// The TV-code sign-in, for liking and disliking comments and posts.
class _TvSignInTile extends StatelessWidget {
  const _TvSignInTile(this.sign, {this.saveSamples, required this.note});
  final YoutubeTvSignIn sign;
  final Future<String> Function()? saveSamples;
  final TextStyle note;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final error = sign.error;
    final code = sign.code;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      switch (sign.state) {
        TvSignInState.signedIn => ListTile(
            leading: Icon(AppIcons.thumbsUp, color: colors.primary),
            title: Text(sign.name ?? tr('已用电视码登录')),
            subtitle: Text(tr('可以给评论和社区帖子点赞、点踩')),
            trailing: Wrap(spacing: 8, children: [
              if (saveSamples != null)
                TextButton(
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    final result = await saveSamples!();
                    messenger.showSnackBar(SnackBar(content: Text(result)));
                  },
                  child: Text(tr('保存电视版样本')),
                ),
              OutlinedButton(onPressed: sign.signOut, child: Text(tr('退出'))),
            ]),
          ),
        TvSignInState.waiting => ListTile(
            leading: const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5)),
            title: code == null
                ? Text(tr('正在获取电视码…'))
                : Row(children: [
                    Text(tr('电视码：')),
                    SelectableText(code, style: context.text.headlineSmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: 2)),
                    IconButton(tooltip: tr('复制'), icon: const Icon(AppIcons.copySimple, size: 18), onPressed: () => copyText(context, code, tr('已复制电视码'))),
                  ]),
            subtitle: Text(tr('在浏览器打开 {0}，登录 Google 账号后输入上面的电视码，完成后会自动回到这里。', [sign.address])),
            trailing: Wrap(spacing: 8, children: [
              if (code != null) FilledButton.tonal(onPressed: () => openExternal(sign.address), child: Text(tr('打开网页'))),
              TextButton(onPressed: sign.cancel, child: Text(tr('取消'))),
            ]),
          ),
        TvSignInState.signedOut => ListTile(
            leading: Icon(AppIcons.television, color: colors.primary),
            title: Text(tr('未登录')),
            subtitle: Text(tr('在浏览器里输入一串电视码完成登录，不用密码和 Cookie，随时可以在 Google 账号的第三方应用里撤销。')),
            trailing: FilledButton.tonal(onPressed: sign.signIn, child: Text(tr('用电视码登录'))),
          ),
      },
      if (error != null) Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 8), child: ErrorBanner(error)),
    ]);
  }
}

/// The user's own Google Cloud OAuth client, for builds without one or for
/// people who prefer their own quota.
class _ClientSettings extends StatefulWidget {
  const _ClientSettings({required this.account, required this.note});
  final AccountController account;
  final TextStyle note;

  @override
  State<_ClientSettings> createState() => _ClientSettingsState();
}

class _ClientSettingsState extends State<_ClientSettings> {
  late final _id = TextEditingController(text: widget.account.customClient?.id ?? '');
  late final _secret = TextEditingController(text: widget.account.customClient?.secret ?? '');

  @override
  void dispose() {
    _id.dispose();
    _secret.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final account = widget.account;
    final custom = account.customClient != null;
    final candidate = OAuthClientConfig(_id.text.trim(), _secret.text.trim());
    return ExpansionTile(
      key: const PageStorageKey('expand:client'),
      leading: const Icon(AppIcons.key),
      title: Text(tr('自定义 Google 客户端')),
      subtitle: Text(custom
          ? tr('正在使用你自己的客户端')
          : account.client == null
              ? tr('未设置')
              : tr('正在使用内置客户端')),
      initiallyExpanded: account.client == null,
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          tr('1. 在 Google Cloud 控制台新建项目，然后在这个项目里启用 YouTube Data API v3（下面第一个按钮，打开后确认顶部选中的是这个项目，再点“启用”）。没有启用的话，登录后会提示“还没有启用 YouTube Data API v3”。\n2. 配置 OAuth 同意屏幕，用户类型选“外部”，把自己的 Google 账号加为测试用户。\n3. 在“凭据”里创建 OAuth 客户端 ID，应用类型选“桌面应用”，把客户端 ID 和密钥填到下面。'),
          style: widget.note,
        ),
        const SizedBox(height: 4),
        Wrap(spacing: 8, children: [
          TextButton.icon(
            onPressed: () => openExternal(YouTubeApiException.enableApiUrl),
            icon: const Icon(AppIcons.arrowSquareOut, size: 18),
            label: Text(tr('启用 YouTube Data API v3')),
          ),
          TextButton.icon(
            onPressed: () => openExternal('https://console.cloud.google.com/apis/credentials'),
            icon: const Icon(AppIcons.arrowSquareOut, size: 18),
            label: Text(tr('创建 OAuth 客户端')),
          ),
        ]),
        const SizedBox(height: 8),
        // Each field gets its own storage key: a text field scrolls, and
        // without one its scroll offset would be read back from the
        // tile's own saved open/closed flag, a bool, and fail to build.
        TextField(
            key: const PageStorageKey('client:id'), controller: _id, onChanged: (_) => setState(() {}), decoration: InputDecoration(labelText: tr('客户端 ID'), hintText: '…apps.googleusercontent.com')),
        const SizedBox(height: 8),
        TextField(key: const PageStorageKey('client:secret'), controller: _secret, onChanged: (_) => setState(() {}), obscureText: true, decoration: InputDecoration(labelText: tr('客户端密钥'))),
        const SizedBox(height: 12),
        Wrap(spacing: 8, children: [
          FilledButton.tonal(
            onPressed: candidate.isValid ? () => _apply(candidate) : null,
            child: Text(tr('保存')),
          ),
          if (custom)
            TextButton(
              onPressed: () {
                _id.clear();
                _secret.clear();
                _apply(null);
              },
              child: Text(OAuthClientConfig.builtIn.isValid ? tr('改回内置客户端') : tr('清除')),
            ),
        ]),
      ],
    );
  }

  Future<void> _apply(OAuthClientConfig? config) async {
    final messenger = ScaffoldMessenger.of(context);
    final wasSignedIn = widget.account.signedIn;
    await widget.account.setCustomClient(config);
    messenger.showSnackBar(SnackBar(content: Text(wasSignedIn ? tr('客户端已更换，请重新登录') : tr('客户端已保存'))));
  }
}

/// Account entry in the top bar.
class AccountButton extends StatelessWidget {
  const AccountButton({super.key, required this.account, required this.onOpenSettings});
  final AccountController? account;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final account = this.account;
    final signedIn = account?.signedIn ?? false;
    final name = account?.name ?? '';
    final avatar = CircleAvatar(
      radius: 16,
      backgroundColor: signedIn ? colors.primaryContainer : colors.surfaceContainerHighest,
      child: signedIn && name.isNotEmpty
          ? Text(String.fromCharCode(name.runes.first).toUpperCase(), style: TextStyle(fontWeight: FontWeight.w600, color: colors.onPrimaryContainer))
          : Icon(AppIcons.user, size: 20, color: colors.onSurfaceVariant),
    );
    if (account == null || !signedIn) {
      return IconButton(tooltip: tr('登录 Google 账号（可选）'), onPressed: onOpenSettings, icon: avatar);
    }
    return PopupMenuButton<String>(
      tooltip: name.isEmpty ? tr('账号') : name,
      icon: avatar,
      onSelected: (value) => value == 'sync' ? account.sync() : onOpenSettings(),
      itemBuilder: (context) => [
        PopupMenuItem(enabled: false, child: Text(name.isEmpty ? tr('YouTube 账号') : name, style: context.text.titleSmall)),
        PopupMenuItem(value: 'sync', enabled: !account.syncing, child: ListTile(dense: true, leading: const Icon(AppIcons.arrowsCounterClockwise), title: Text(account.syncing ? tr('正在同步…') : tr('同步订阅和播放列表')))),
        PopupMenuItem(value: 'settings', child: ListTile(dense: true, leading: Icon(AppIcons.userGear), title: Text(tr('账号设置')))),
      ],
    );
  }
}
