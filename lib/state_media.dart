import 'blocked_groups.dart';

final _all = BlockMatcher(stateMedia.where((g) => g.onByDefault).toList());

/// Whether a channel called [channel] is one of [stateMedia], other than
/// the groups the user [allowed]. Only the channel's name counts, so a
/// video that merely mentions CGTN stays: a name that is one of the listed
/// names or starts with one followed by a space or sign ("RT Documentary",
/// "CGTN Français") counts.
bool isStateMediaChannel(String channel, [Set<String>? allowed]) =>
    (allowed == null ? _all : BlockMatcher(stateMedia, allowedGroups: allowed)).channel(channel);
