import 'dart:io';
import 'dart:isolate';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../app/library_controller.dart';
import '../../app_directories.dart';
import '../../app_log.dart';
import '../../app/subscription_import_actions.dart';
import '../../l10n/l10n.dart';
import '../../subscription_import.dart';
import '../../friendly_error.dart';

/// Asks for a NewPipe, FreeTube or Google Takeout file, follows its channels
/// and says what happened. The file is read here and goes nowhere else.
Future<void> importSubscriptionsFromFile(BuildContext context, LibraryController library) async {
  final messenger = ScaffoldMessenger.of(context);
  void say(String message) => messenger.showSnackBar(SnackBar(content: Text(message)));
  final SubscriptionImport data;
  try {
    final file = await openFile(acceptedTypeGroups: [
      XTypeGroup(label: tr('Subscription export'), extensions: const ['json', 'db', 'csv', 'opml', 'xml', 'txt'])
    ]);
    if (file == null) return;
    if (await file.length() > maxSubscriptionFileBytes) {
      say(tr('That file is too large to be a subscription export (over {0} MB)', [maxSubscriptionFileBytes >> 20]));
      return;
    }
    data = await parseSubscriptionsInBackground(await file.readAsBytes());
  } catch (_) {
    say(tr('Could not open the file'));
    return;
  }
  if (data.channels.isEmpty) {
    say(tr('No YouTube channels were found in this file. Use a NewPipe, FreeTube or Google Takeout subscriptions export.'));
    return;
  }
  final outcome = followImported(library, data);
  say(tr('Imported: {0} added, {1} already followed, {2} skipped', [outcome.added, outcome.already, outcome.skipped]));
}

/// Saves the followed channels as a NewPipe subscriptions file, which
/// NewPipe, FreeTube, LibreTube and Lumtub's own import can read.
Future<void> exportSubscriptionsToFile(BuildContext context, LibraryController library) async {
  final messenger = ScaffoldMessenger.of(context);
  void say(String message) => messenger.showSnackBar(SnackBar(content: Text(message)));
  final channels = [for (final channel in library.channels) (channel.id, channel.name)];
  if (channels.isEmpty) {
    say(tr('No followed channels to export'));
    return;
  }
  final now = DateTime.now();
  final name = 'Lumtub_subscriptions_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}.json';
  final location = await getSaveLocation(suggestedName: name, acceptedTypeGroups: const [XTypeGroup(label: 'JSON', extensions: ['json'])]);
  if (location == null) return;
  try {
    await writeFileAtomic(File(location.path), await Isolate.run(() => newPipeSubscriptions(channels)));
    say(tr('Exported {0} channels', [channels.length]));
  } catch (e) {
    logError('Could not export subscriptions', e);
    say(tr('Export failed: {0}', [friendlyFileError(e)]));
  }
}
