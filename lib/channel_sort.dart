import 'l10n/l10n.dart';
import 'models.dart';
import 'video_repository.dart' show ChannelTab;

/// The order of a channel's uploads: YouTube's own sort chips, and by
/// length, which YouTube does not offer: the whole tab is read and ordered
/// here.
enum ChannelSort {
  latest('Latest', 'Latest'),
  popular('Popular', 'Popular'),
  oldest('Oldest', 'Oldest'),
  longest('Longest', null),
  shortest('Shortest', null);

  const ChannelSort(this._label, this.chip);
  final String _label;

  /// The chip's text in YouTube's English interface; null for an order
  /// made here from the newest-first listing.
  final String? chip;
  String get label => tr(_label);

  /// How the videos rank, highest first, for an order made here. A video
  /// of unknown length, such as an upcoming stream, comes last either way.
  double Function(VideoItem item)? get rank => switch (this) {
        longest => (item) => (item.duration ?? -1).toDouble(),
        shortest => (item) => -(item.duration ?? _unknown).toDouble(),
        _ => null,
      };
  static const _unknown = 1 << 40;

  /// How many videos one reading of the tab takes in, for an order made
  /// here; scrolling to the end reads on from there.
  static const wholeTab = 2000;

  /// Whether this order fits [tab]: every Short is about as short as the
  /// next, so they are not ordered by length.
  bool fits(ChannelTab tab) => rank == null || tab != ChannelTab.shorts;
}

/// The continuation token of each sort chip in a channel tab response, by
/// the chip's text. Both the older chip cloud and the newer chip view
/// models are read.
Map<String, String> sortChipTokens(Object? response) {
  final tokens = <String, String>{};
  void walk(Object? node) {
    if (node is List) {
      node.forEach(walk);
    } else if (node is Map) {
      final chip = node['chipCloudChipRenderer'] ?? node['chipViewModel'];
      if (chip is Map) {
        final text = _text(chip['text']) ?? _text(chip['title']);
        final token = _token(chip);
        if (text != null && token != null) tokens.putIfAbsent(text, () => token);
      } else {
        node.values.forEach(walk);
      }
    }
  }

  walk(response);
  return tokens;
}

String? _text(Object? value) {
  if (value is String) return value;
  if (value is Map) {
    final simple = value['simpleText'] ?? value['content'];
    if (simple is String) return simple;
    final runs = value['runs'];
    if (runs is List) return runs.map((r) => r is Map ? r['text'] ?? '' : '').join();
  }
  return null;
}

String? _token(Object? node) {
  if (node is Map) {
    final command = node['continuationCommand'];
    if (command is Map && command['token'] is String) return command['token'] as String;
    for (final value in node.values) {
      final found = _token(value);
      if (found != null) return found;
    }
  } else if (node is List) {
    for (final value in node) {
      final found = _token(value);
      if (found != null) return found;
    }
  }
  return null;
}
