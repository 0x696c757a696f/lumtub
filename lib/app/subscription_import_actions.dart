import '../models.dart';
import '../subscription_import.dart';
import 'library_controller.dart';

/// What importing a follow list from a file did.
class ImportOutcome {
  const ImportOutcome({required this.added, required this.already, required this.skipped});
  final int added;
  final int already;
  final int skipped;
}

/// Follows the channels of [data] that are not followed yet, then looks up
/// pictures for the new ones in the background, a few at a time.
ImportOutcome followImported(LibraryController library, SubscriptionImport data) {
  final channels = [for (final (id, name) in data.channels) ChannelRef(id, name)];
  final added = library.followAll(channels);
  if (added > 0) library.fillMissingAvatars();
  return ImportOutcome(added: added, already: channels.length - added, skipped: data.skipped);
}
