import 'l10n/l10n.dart';

/// The order of a channel's uploads, as YouTube's sort chips offer it.
enum ChannelSort {
  latest('Latest', 'Latest'),
  popular('Popular', 'Popular'),
  oldest('Oldest', 'Oldest');

  const ChannelSort(this._label, this.chip);
  final String _label;

  /// The chip's text in YouTube's English interface.
  final String chip;
  String get label => tr(_label);
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
