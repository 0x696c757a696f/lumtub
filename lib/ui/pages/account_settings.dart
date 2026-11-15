import 'package:flutter/material.dart';

import '../../app/account_controller.dart';
import '../../google_auth.dart';
import '../../youtube_account.dart';
import '../../youtube_tv_sign_in.dart';
import '../../youtube_web_sign_in.dart';
import '../common.dart';
import '../theme.dart';
import 'cookie_sign_in_tile.dart';
import 'channel_page.dart' show ChannelAvatar;
import '../../l10n/l10n.dart';
import '../app_icons.dart';
import '../sign_in_row.dart';

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
    if (account == null) return ListTile(title: Text(tr('Preparing…')));
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
            title: tr('Google sign-in'),
            purpose: tr('Sync subscriptions and playlists; like, comment and subscribe. Recommended; most people need only this one'),
            signedIn: account.signedIn,
            expanded: true,
            children: [
              switch (account.state) {
                AccountState.signedIn => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SignInRow(
                      leading: account.avatar == null
                          ? CircleAvatar(
                              backgroundColor: colors.primaryContainer,
                              child: Icon(AppIcons.userFill, color: colors.onPrimaryContainer),
                            )
                          : ChannelAvatar(name: account.name ?? '', image: account.avatar, radius: 20),
                      title: Text(account.name ?? tr('YouTube account')),
                      subtitle: Text(account.syncing
                          ? tr('Syncing subscriptions and playlists…')
                          : account.lastSync == null
                              ? tr('Signed in, not synced yet')
                              : tr('Last synced: {0} {1}', [formatDate(account.lastSync!), _time(account.lastSync!)])),
                      actions: [if (!account.canWrite) FilledButton.tonal(onPressed: account.signIn, child: Text(tr('Sign in again to enable likes and comments')))],
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Wrap(spacing: 8, runSpacing: 8, children: [
                        FilledButton.tonalIcon(
                          onPressed: account.syncing ? null : account.sync,
                          icon: account.syncing ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : Icon(AppIcons.arrowsCounterClockwise),
                          label: Text(tr('Sync now')),
                        ),
                        OutlinedButton(onPressed: () => _confirmSignOut(context, account), child: Text(tr('Sign out'))),
                      ]),
                    ),
                  ]),
                AccountState.signingIn => SignInRow(
                    leading: const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5)),
                    title: Text(tr('Finish signing in in your browser')),
                    subtitle: Text(tr("The Google sign-in page has opened in your default browser. You'll return here automatically when done.")),
                    actions: [TextButton(onPressed: account.cancelSignIn, child: Text(tr('Cancel')))],
                  ),
                AccountState.signedOut => SignInRow(
                    leading: Icon(AppIcons.userCircle, color: colors.primary),
                    title: Text(tr('Signed out')),
                    subtitle: Text(account.client == null ? tr('This build has no built-in Google client. Enter your own client below first.') : tr('After signing in you can import subscriptions, playlists and liked videos, and also like, comment, save to playlists and subscribe.')),
                    actions: [
                      FilledButton.icon(
                        onPressed: account.client == null ? null : account.signIn,
                        icon: Icon(AppIcons.signIn),
                        label: Text(tr('Sign in')),
                      ),
                    ],
                  ),
              },
              if (error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: error == YouTubeApiException.apiNotEnabled ? ErrorBanner(error, onRetry: () => openExternal(YouTubeApiException.enableApiUrl), retryLabel: tr('Enable it')) : ErrorBanner(error),
                ),
              _ClientSettings(account: account, note: note),
            ],
          ),
          if (tv != null)
            _Section(
              number: 2,
              title: tr('TV-code sign-in'),
              purpose: tr("YouTube's home feed and watch history; like comments"),
              signedIn: tv.signedIn,
              expanded: tv.signedIn || tv.state == TvSignInState.waiting || tv.error != null,
              children: [
                _TvSignInTile(tv, saveSamples: saveTvSamples, note: note),
                if (_differentAccounts(account, tv) case final names?)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: ErrorBanner(tr('The two sign-ins show different accounts (Google: {0}, TV code: {1}). If they are not the same account, subscriptions and likes end up split between them; sign out of one and sign in again.', [names.$1, names.$2])),
                  ),
              ],
            ),
          if (web != null)
            _Section(
              number: tv == null ? 2 : 3,
              title: tr('Browser sign-in'),
              purpose: tr('For liking, voting and commenting on community posts, writing in live chat, and playing members-only videos'),
              signedIn: web.signedIn,
              expanded: web.signedIn || web.waiting || web.error != null,
              children: [CookieSignInTile(web, note: note)],
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Text(
              tr('Use the same Google account for each sign-in. Sign-ins are kept encrypted on this PC. Lumtub changes your account only when you like, comment, save or subscribe in it, and never uploads your local watch history. Playback does not use an account, so members-only or age-restricted videos may not play.'),
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
              title: Text(tr('Sign out of Google?')),
              content: Text(tr("This deletes the sign-in credentials saved on this device and asks Google to revoke Lumtub's access. Imported followed channels and playlists are kept.")),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('Cancel'))),
                FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(tr('Sign out'))),
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
          Text(tr('Signing in is optional'), style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(tr('Search and playback work without it. Sign in only to the one with the feature you want; ticked ones are signed in.'), style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant)),
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
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: colors.outlineVariant)),
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
        TvSignInState.signedIn => SignInRow(
            leading: Icon(AppIcons.thumbsUp, color: colors.primary),
            title: Text(sign.name ?? tr('Signed in with a TV code')),
            subtitle: Text(tr('You can like and dislike comments and community posts')),
            actions: [
              if (saveSamples != null)
                TextButton(
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    final result = await saveSamples!();
                    messenger.showSnackBar(SnackBar(content: Text(result)));
                  },
                  child: Text(tr('Save TV samples')),
                ),
              OutlinedButton(onPressed: sign.signOut, child: Text(tr('Exit'))),
            ],
          ),
        // Laid out down the page, not as a list row: the code, the steps
        // and the buttons each get the full width, which a phone needs.
        TvSignInState.waiting => Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                // Only while the code is coming; once it shows, the page waits on the person.
                if (code == null) ...[
                  const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5)),
                  const SizedBox(width: 12),
                ],
                Expanded(child: Text(code == null ? tr('Getting a TV code…') : tr('TV code: '))),
              ]),
              if (code != null)
                Row(children: [
                  // Plain text: selectable text under a FittedBox has no width
                  // to lay out in and drew as an empty grey block.
                  Flexible(child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(code, maxLines: 1, style: context.text.headlineSmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: 2)),
                  )),
                  IconButton(tooltip: tr('Copy'), icon: Icon(AppIcons.copySimple, size: 18), onPressed: () => copyText(context, code, tr('TV code copied'))),
                ]),
              const SizedBox(height: 4),
              Text(tr('Open {0} in a browser, sign in to Google and enter the TV code above. This page continues by itself once you are done.', [sign.address]), style: context.text.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                if (code != null) FilledButton.tonal(onPressed: () => openExternal(sign.address), child: Text(tr('Open page'))),
                TextButton(onPressed: sign.cancel, child: Text(tr('Cancel'))),
              ]),
            ]),
          ),
        TvSignInState.signedOut => SignInRow(
            leading: Icon(AppIcons.television, color: colors.primary),
            title: Text(tr('Signed out')),
            subtitle: Text(tr('Sign in by entering a TV code in a browser. No password or cookies; revoke it any time under third-party apps in your Google account.')),
            actions: [FilledButton.tonal(onPressed: sign.signIn, child: Text(tr('Sign in with a TV code')))],
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
      leading: Icon(AppIcons.key),
      title: Text(tr('Custom Google client')),
      subtitle: Text(custom
          ? tr('Using your own client')
          : account.client == null
              ? tr('Not set')
              : tr('Using the built-in client')),
      initiallyExpanded: account.client == null,
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          tr('1. Create a project in the Google Cloud console, then enable YouTube Data API v3 in that project (the first button below; check that this project is selected at the top, then click "Enable"). Without it, signing in reports that YouTube Data API v3 is not enabled.\n2. Set up the OAuth consent screen with user type "External" and add your own Google account as a test user.\n3. Under "Credentials", create an OAuth client ID of type "Desktop app" and enter its client ID and secret below.'),
          style: widget.note,
        ),
        const SizedBox(height: 4),
        Wrap(spacing: 8, children: [
          TextButton.icon(
            onPressed: () => openExternal(YouTubeApiException.enableApiUrl),
            icon: Icon(AppIcons.arrowSquareOut, size: 18),
            label: Text(tr('Enable YouTube Data API v3')),
          ),
          TextButton.icon(
            onPressed: () => openExternal('https://console.cloud.google.com/apis/credentials'),
            icon: Icon(AppIcons.arrowSquareOut, size: 18),
            label: Text(tr('Create OAuth client')),
          ),
        ]),
        const SizedBox(height: 8),
        // Each field gets its own storage key: a text field scrolls, and
        // without one its scroll offset would be read back from the
        // tile's own saved open/closed flag, a bool, and fail to build.
        TextField(
            key: const PageStorageKey('client:id'), controller: _id, onChanged: (_) => setState(() {}), decoration: InputDecoration(labelText: tr('Client ID'), hintText: '…apps.googleusercontent.com')),
        const SizedBox(height: 8),
        TextField(key: const PageStorageKey('client:secret'), controller: _secret, onChanged: (_) => setState(() {}), obscureText: true, decoration: InputDecoration(labelText: tr('Client secret'))),
        const SizedBox(height: 12),
        Wrap(spacing: 8, children: [
          FilledButton.tonal(
            onPressed: candidate.isValid ? () => _apply(candidate) : null,
            child: Text(tr('Save')),
          ),
          if (custom)
            TextButton(
              onPressed: () {
                _id.clear();
                _secret.clear();
                _apply(null);
              },
              child: Text(OAuthClientConfig.builtIn.isValid ? tr('Revert to built-in client') : tr('Clear')),
            ),
        ]),
      ],
    );
  }

  Future<void> _apply(OAuthClientConfig? config) async {
    final messenger = ScaffoldMessenger.of(context);
    final wasSignedIn = widget.account.signedIn;
    await widget.account.setCustomClient(config);
    messenger.showSnackBar(SnackBar(content: Text(wasSignedIn ? tr('Client changed. Please sign in again') : tr('Client saved'))));
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
    final avatar = signedIn && account?.avatar != null
        // The picture, or the name's first letter while it cannot load.
        ? ChannelAvatar(name: name, image: account!.avatar, radius: 16)
        : CircleAvatar(
            radius: 16,
            backgroundColor: signedIn ? colors.primaryContainer : colors.surfaceContainerHighest,
            child: signedIn && name.isNotEmpty
                ? Text(String.fromCharCode(name.runes.first).toUpperCase(), style: TextStyle(fontWeight: FontWeight.w600, color: colors.onPrimaryContainer))
                : Icon(AppIcons.user, size: 20, color: colors.onSurfaceVariant),
          );
    if (account == null || !signedIn) {
      return IconButton(tooltip: tr('Sign in with Google (optional)'), onPressed: onOpenSettings, icon: avatar);
    }
    return PopupMenuButton<String>(
      tooltip: name.isEmpty ? tr('Account') : name,
      icon: avatar,
      onSelected: (value) => value == 'sync' ? account.sync() : onOpenSettings(),
      itemBuilder: (context) => [
        PopupMenuItem(enabled: false, child: Text(name.isEmpty ? tr('YouTube account') : name, style: context.text.titleSmall)),
        PopupMenuItem(value: 'sync', enabled: !account.syncing, child: ListTile(dense: true, leading: Icon(AppIcons.arrowsCounterClockwise), title: Text(account.syncing ? tr('Syncing…') : tr('Sync subscriptions and playlists')))),
        PopupMenuItem(value: 'settings', child: ListTile(dense: true, leading: Icon(AppIcons.userGear), title: Text(tr('Account settings')))),
      ],
    );
  }
}
