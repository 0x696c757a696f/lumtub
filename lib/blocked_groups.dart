import 'dart:convert';
import 'dart:ffi';

import 'l10n/l10n.dart';
import 'models.dart';
import 'native_core.dart';

/// The block lists, kept as text files under lists/ (see lists/schema.md)
/// and built into lumtub_core, which reads and checks them. Each list is a
/// [BlockedGroup]. Only channel names, @handles and channel ids are
/// matched, never titles or descriptions: other channels' reports about a
/// group, and searches for its names, stay.
class BlockLists {
  BlockLists._(this.all, {this.version = 0, this.downloaded = false});

  /// Where a downloaded, signed lists.json is kept; set before the lists
  /// are first read.
  static String? folder;

  /// Every list in use, read once from lumtub_core; none without it. A
  /// newer download (lib/block_list_updates.dart) is used from the next
  /// start.
  static final BlockLists instance = _read();

  final List<BlockedGroup> all;
  /// When the lists were last changed, in seconds since 1970; 0 when not
  /// known.
  final int version;
  /// Whether they came from a download rather than this build.
  final bool downloaded;

  static BlockLists _read() {
    final core = NativeCore.instance;
    final text = core?.take(core.withText(jsonEncode({'folder': folder ?? ''}), core.blockLists));
    if (text == null) return BlockLists._(const []);
    final json = jsonDecode(text) as Map<String, dynamic>;
    final lists = json['lists'] as List<dynamic>;
    return BlockLists._(
      [for (final list in lists) BlockedGroup.fromJson(list as Map<String, dynamic>)],
      version: (json['version'] as num?)?.toInt() ?? 0,
      downloaded: json['downloaded'] == true,
    );
  }

  /// The signature of the verified download kept in [folder], newer than
  /// this build or not; null when there is none or it does not verify.
  static List<int>? keptSignature(String folder) {
    final core = NativeCore.instance;
    final text = core?.take(core.withText(jsonEncode({'folder': folder}), core.blockLists));
    if (text == null) return null;
    final hex = (jsonDecode(text) as Map<String, dynamic>)['signature'];
    if (hex is! String || hex.length.isOdd) return null;
    return [for (var i = 0; i < hex.length; i += 2) int.parse(hex.substring(i, i + 2), radix: 16)];
  }

  List<BlockedGroup> inCategory(String category) => [for (final list in all) if (list.categories.contains(category)) list];
}

/// Movements that governments or the mainstream churches have called
/// heretical or destructive, with their founders, aliases and media
/// (lists/religion), left out while AppPreferences.blockGroups is on.
final blockedGroups = BlockLists.instance.inCategory('religion');

/// Media a government runs to speak for it (lists/state-media), left out
/// while AppPreferences.blockStateMedia is on. Public broadcasters with
/// editorial independence (BBC, NHK, PBS and the like) are not listed.
final stateMedia = BlockLists.instance.inCategory('state-media');

/// The lists of every other category (scams, malware, fake cures and the
/// rest of lists/schema.md), left out while AppPreferences.blockOtherLists
/// is on. Lists marked label or demote are not acted on yet.
final otherLists = [
  for (final list in BlockLists.instance.all)
    if (!list.categories.contains('religion') && !list.categories.contains('state-media')) list,
];

/// One list: its name, the name shown in settings, and its entries.
class BlockedGroup {
  BlockedGroup({
    required this.name,
    required this.id,
    required String label,
    required this.entries,
    this.categories = const [],
    this.action = 'hide',
    this.defaultOn = false,
    this.onByDefault = true,
    this.note,
  }) : _label = label;

  factory BlockedGroup.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String;
    final legacy = (json['legacy'] as List<dynamic>?)?.cast<String>() ?? const [];
    final name = legacy.isNotEmpty ? legacy.first : id;
    List<String> strings(Object? value) => (value as List<dynamic>?)?.cast<String>() ?? const [];
    return BlockedGroup(
      name: name,
      id: id,
      label: json['name'] as String,
      categories: strings(json['categories']),
      action: json['action'] as String? ?? 'hide',
      defaultOn: json['default_on'] == true,
      onByDefault: json['suggested'] != false,
      note: json['note'] as String?,
      entries: [
        for (final record in (json['records'] as List<dynamic>).cast<Map<String, dynamic>>())
          BlockEntry.fromRecord(name, id, record),
      ],
    );
  }

  /// Saved in the preferences when the user ticks or unticks it: the name
  /// it had before the lists were files (`legacy` in its file), else its id.
  final String name;
  /// The list file's id.
  final String id;
  final String _label;
  String get label => tr(_label);
  final List<String> categories;
  /// hide, quiet, demote or label.
  final String action;
  /// On for a new install (only safety lists may be).
  final bool defaultOn;
  /// Ticked when its category is turned on; `suggested: no` in its file
  /// leaves it for the user to tick.
  final bool onByDefault;
  /// How the group's members relate to a government, shown in settings.
  final String? note;
  final List<BlockEntry> entries;
}

/// How an entry of a block list is matched.
enum BlockKind {
  /// A channel's name, or the start of it ("RT Documentary" for RT).
  channel('Channel names'),
  /// A channel's whole name and nothing longer.
  exact('Whole channel name'),
  handle('@handles'),
  id('Channel ids');

  const BlockKind(this._label);
  final String _label;
  String get label => tr(_label);
}

/// One record of a block list: a channel by its names, @handles and ids.
class BlockEntry {
  const BlockEntry(this.group, this.kind, this.forms, {required this.key, this.prefixes = const [], this.names = const [], this.handles = const [], this.ids = const []});

  factory BlockEntry.fromRecord(String group, String list, Map<String, dynamic> record) {
    List<String> strings(String key) => (record[key] as List<dynamic>?)?.cast<String>() ?? const [];
    final prefixes = strings('prefixes'), names = strings('names'), ids = strings('ids');
    final handles = [for (final h in strings('handles')) '@$h'];
    final (kind, forms) = prefixes.isNotEmpty
        ? (BlockKind.channel, prefixes)
        : names.isNotEmpty
            ? (BlockKind.exact, names)
            : handles.isNotEmpty
                ? (BlockKind.handle, handles)
                : (BlockKind.id, ids);
    final legacy = strings('legacy');
    return BlockEntry(
      group,
      kind,
      [...forms, if (kind != BlockKind.exact) ...names, if (kind != BlockKind.handle) ...handles, if (kind != BlockKind.id) ...ids],
      key: legacy.isNotEmpty ? legacy.first : '$list/${record['slug']}',
      prefixes: prefixes,
      names: names,
      handles: handles,
      ids: ids,
    );
  }

  final String group;
  final BlockKind kind;
  /// Its spellings, the first shown.
  final List<String> forms;
  String get label => forms.first;
  /// Saved in AppPreferences.allowedEntries when the user unticks it.
  final String key;
  final List<String> prefixes;
  final List<String> names;
  final List<String> handles;
  final List<String> ids;
}

/// Tests videos and channels against block lists, leaving out the groups
/// and entries the user unticked. Built once per preferences; the matching
/// is done by lumtub_core (native/lumtub_core/src/filter.rs).
class BlockMatcher implements Finalizable {
  factory BlockMatcher(List<BlockedGroup> groups, {Set<String> allowedGroups = const {}, Set<String> allowedEntries = const {}}) {
    final channels = <String>{}, exact = <String>{}, handles = <String>{}, ids = <String>{};
    for (final group in groups) {
      if (allowedGroups.contains(group.name)) continue;
      for (final entry in group.entries) {
        if (allowedEntries.contains(entry.key)) continue;
        channels.addAll(entry.prefixes.map((p) => p.toLowerCase()));
        exact.addAll(entry.names.map((n) => n.toLowerCase()));
        handles.addAll(entry.handles.map((h) => h.toLowerCase()));
        ids.addAll(entry.ids);
      }
    }
    final core = NativeCore.instance;
    if (core == null) return BlockMatcher._(null, nullptr);
    final json = jsonEncode({'channels': channels.toList(), 'exact': exact.toList(), 'handles': handles.toList(), 'ids': ids.toList()});
    final handle = core.withText(json, core.blocksNew);
    final matcher = BlockMatcher._(core, handle);
    if (handle != nullptr) core.blocksFinalizer.attach(matcher, handle.cast());
    return matcher;
  }

  BlockMatcher._(this._core, this._handle);

  final NativeCore? _core;
  final Pointer<Void> _handle;

  /// Whether a channel called [name], with [id] or [handle] if known, is
  /// listed.
  bool channel(String name, {String? id, String? handle}) {
    final core = _core;
    if (core == null || _handle == nullptr) return false;
    final json = jsonEncode({'n': name, if (id != null) 'i': id, if (handle != null) 'h': handle});
    return core.withText(json, (bytes, length) => core.blocksMatch(_handle, bytes, length));
  }
}

final _all = BlockMatcher(blockedGroups.where((g) => g.onByDefault).toList());

/// Whether [item]'s channel is one of [blockedGroups]' channels. Its title
/// and description do not count.
bool namesBlockedGroup(VideoItem item) => _all.channel(item.channel, id: item.channelId);

/// Whether [query] is [name] exactly, letter case included, apart from the
/// spaces around it: one character more or less does not count.
bool isExactName(String name, String? query) {
  final typed = query?.trim() ?? '';
  return typed.isNotEmpty && typed == name.trim();
}
