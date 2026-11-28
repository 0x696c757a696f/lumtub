import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../l10n/l10n.dart';
import '../../scrobble.dart';
import '../../widgets/settings_tiles.dart';
import '../app_icons.dart';
import '../common.dart';

/// 听歌记录: the ListenBrainz row of Settings › Account.
class ScrobbleSettings extends StatefulWidget {
  const ScrobbleSettings({super.key, required this.scrobbler});
  final Scrobbler scrobbler;

  @override
  State<ScrobbleSettings> createState() => _ScrobbleSettingsState();
}

class _ScrobbleSettingsState extends State<ScrobbleSettings> {
  Scrobbler get _scrobbler => widget.scrobbler;

  String get _status {
    final scrobbler = _scrobbler;
    if (!scrobbler.connected) {
      return tr(
          'Off. Songs you listen to can be added to your ListenBrainz listening history; other videos are never sent');
    }
    if (scrobbler.tokenRefused) {
      return tr('ListenBrainz no longer accepts the token. Tap to enter a new one');
    }
    final user = scrobbler.user ?? '';
    return scrobbler.waiting > 0
        ? tr('Connected as {0} · {1} listens waiting to be sent', [user, scrobbler.waiting])
        : tr('Connected as {0}', [user]);
  }

  @override
  Widget build(BuildContext context) => NormalItem(
        title: tr('Scrobble songs to ListenBrainz'),
        subtitle: _status,
        leading: Icon(AppIcons.musicNotes),
        onTap: () => unawaited(_open(context)),
      );

  Future<void> _open(BuildContext context) async {
    final scrobbler = _scrobbler;
    if (scrobbler.connected && !scrobbler.tokenRefused) {
      final disconnect = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('ListenBrainz'),
          content: Text(tr(
              'Connected as {0}. A song counts once you have listened to half of it or four minutes, whichever comes first. Nothing is sent in incognito mode.',
              [scrobbler.user ?? ''])),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, true), child: Text(tr('Disconnect'))),
            FilledButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('Close'))),
          ],
        ),
      );
      if (disconnect ?? false) {
        await scrobbler.disconnect();
        if (mounted) setState(() {});
      }
      return;
    }
    final connected = await showDialog<bool>(
        context: context, builder: (context) => _TokenDialog(scrobbler: scrobbler));
    if (!mounted) return;
    setState(() {});
    if ((connected ?? false) && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(tr('Connected as {0}', [scrobbler.user ?? '']))));
    }
  }
}

class _TokenDialog extends StatefulWidget {
  const _TokenDialog({required this.scrobbler});
  final Scrobbler scrobbler;

  @override
  State<_TokenDialog> createState() => _TokenDialogState();
}

class _TokenDialogState extends State<_TokenDialog> {
  final _token = TextEditingController();
  bool _checking = false;
  String? _error;

  @override
  void dispose() {
    _token.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final token = _token.text.trim();
    if (token.isEmpty || _checking) return;
    setState(() {
      _checking = true;
      _error = null;
    });
    try {
      await widget.scrobbler.connect(token);
      if (mounted) Navigator.pop(context, true);
    } on ScrobbleException catch (e) {
      if (mounted) {
        setState(() {
          _checking = false;
          _error = e.badToken
              ? tr('ListenBrainz did not accept this token')
              : tr("Couldn't reach ListenBrainz. Check your network and try again");
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _checking = false;
          _error = tr("Couldn't save the token");
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(tr('Connect ListenBrainz')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr(
                'Copy your user token from your ListenBrainz settings page and paste it here. It is stored encrypted on this device.')),
            const SizedBox(height: 4),
            TextButton.icon(
              onPressed: () => unawaited(openExternal('https://listenbrainz.org/settings/')),
              icon: Icon(AppIcons.link),
              label: Text(tr('Open ListenBrainz settings')),
            ),
            TextField(
              controller: _token,
              autofocus: true,
              obscureText: true,
              enabled: !_checking,
              decoration: InputDecoration(hintText: tr('User token'), errorText: _error),
              onSubmitted: (_) => unawaited(_connect()),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: _checking ? null : () => Navigator.pop(context, false),
              child: Text(tr('Cancel'))),
          FilledButton(
              onPressed: _checking ? null : () => unawaited(_connect()),
              child: Text(_checking ? tr('Checking…') : tr('Connect'))),
        ],
      );
}
