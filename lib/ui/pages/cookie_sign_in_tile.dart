import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../youtube_web_sign_in.dart';
import '../common.dart';
import '../theme.dart';
import '../../l10n/l10n.dart';
import '../app_icons.dart';
import '../sign_in_row.dart';

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
          ? tr('Touch ID or password')
          : null;

  static String _guard(CookieGuard? guard) => switch (guard) {
        CookieGuard.presence => tr('Protected by {0}: confirmed once the first time it is needed after Lumtub starts', [_presenceName ?? tr('system confirmation')]),
        CookieGuard.hardware => tr("Encrypted with this PC's TPM chip; a copy cannot be opened anywhere else"),
        CookieGuard.keyring => tr('Kept encrypted in the system keychain'),
        CookieGuard.account => tr('Encrypted with your Windows account (this PC has no usable TPM)'),
        CookieGuard.file => tr('Protected only by file permissions (this device has no usable system keychain)'),
        null => tr('Kept encrypted'),
      };

  Future<void> _import() async {
    final file = await openFile(acceptedTypeGroups: [
      XTypeGroup(label: tr('Cookie file'), extensions: const ['txt'])
    ]);
    if (file == null || !mounted) return;
    var delete = true;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(tr('Import cookies.txt?')),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('Only the youtube.com cookies are taken and kept encrypted on this device.')),
            const SizedBox(height: 8),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: delete,
              onChanged: (value) => setState(() => delete = value ?? true),
              title: Text(tr('Wipe and delete the file after importing (recommended)')),
              subtitle: Text(tr('A cookies.txt left on disk is plain text: anyone who gets it can use your account.')),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('Cancel'))),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(tr('Import'))),
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
          SignInRow(
            leading: const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5)),
            title: Text(sign.reading
                ? tr('Reading the sign-in…')
                : sign.browser == null
                    ? tr('Opening the browser…')
                    : tr('Sign in to YouTube in the {0} window', [sign.browser!])),
            subtitle: Text(tr("Once YouTube's home page shows, close this browser window and Lumtub reads the sign-in. It is a separate temporary window and never touches your usual browser's data.")),
            actions: [if (sign.browser != null && !sign.reading) TextButton(onPressed: sign.cancel, child: Text(tr('Cancel')))],
          )
        else if (sign.signedIn)
          SignInRow(
            leading: Icon(AppIcons.lock, color: colors.primary),
            title: Text(tr('Signed in with a browser')),
            subtitle: Text('${tr('You can like, vote in and comment on community posts')}\n${_guard(sign.guard)}'),
            actions: [OutlinedButton(onPressed: sign.signOut, child: Text(tr('Exit')))],
          )
        else ...[
          SignInRow(
            leading: Icon(AppIcons.globe, color: colors.primary),
            title: Text(tr('Signed out')),
            subtitle: Text(tr("Sign in in a temporary browser window. Lumtub takes only the youtube.com cookies, keeps them encrypted, then deletes all of that window's data.")),
            actions: [FilledButton.tonal(onPressed: () => sign.signInWithBrowser(presence: _presence), child: Text(tr('Sign in with a browser')))],
          ),
          if (presence != null)
            SwitchListTile(
              value: _presence,
              onChanged: (value) => setState(() => _presence = value),
              title: Text(tr('Protect with {0}', [presence])),
              subtitle: Text(tr('Confirm once the first time the sign-in is needed after Lumtub starts. Other programs on the computer cannot open the cookies unnoticed.')),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Align(alignment: AlignmentDirectional.centerStart, child: TextButton.icon(onPressed: _import, icon: Icon(AppIcons.fileText, size: 18), label: Text(tr('Import a cookies.txt instead')))),
          ),
        ],
        if (error != null) Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 8), child: ErrorBanner(error)),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Text(
            tr("Cookies are the account's signed-in session, so a secondary account is a good idea. They stay in Lumtub's native core, out of reach of the interface and the log, and go only to youtube.com. Signing out of all devices in your Google account ends them."),
            style: widget.note,
          ),
        ),
      ]),
    );
  }
}
