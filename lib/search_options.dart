import 'dart:convert';

import 'video_repository.dart';
import 'l10n/l10n.dart';

/// How YouTube orders search results.
enum SearchSort {
  relevance('Relevance', 0),
  date('Upload date', 2),
  views('Views', 3),
  rating('Rating', 1);

  const SearchSort(this._label, this.code);
  final String _label;
  String get label => tr(_label);
  final int code;
}

enum SearchUploadDate {
  any('Any time', 0),
  hour('Last hour', 1),
  today('Today', 2),
  week('This week', 3),
  month('This month', 4),
  year('This year', 5);

  const SearchUploadDate(this._label, this.code);
  final String _label;
  String get label => tr(_label);
  final int code;
}

enum SearchDuration {
  any('Any duration', 0),
  short('Under 4 minutes', 1),
  medium('4–20 minutes', 3),
  long('Over 20 minutes', 2);

  const SearchDuration(this._label, this.code);
  final String _label;
  String get label => tr(_label);
  final int code;
}

/// Picture features a video must have.
enum SearchQuality {
  any('Any quality', []),
  hd('HD 1080p', [0x20, 1]),
  uhd('4K', [0x70, 1]),
  hdr('HDR', [0xC8, 0x01, 1]);

  const SearchQuality(this._label, this.bytes);
  final String _label;
  String get label => tr(_label);
  /// The filter's field in YouTube's `sp` (HD 4, 4K 14, HDR 25), encoded.
  final List<int> bytes;
}

/// YouTube's `sp` search parameter: a protobuf message, base64-encoded,
/// with the sort order in field 1 and the filters in message field 2
/// (upload date 1, type 2, duration 3, live 8, and the [SearchQuality]
/// fields). Null when nothing is set,
/// which YouTube reads as relevance without filters.
String? searchParams({
  SearchFilter type = SearchFilter.all,
  SearchSort sort = SearchSort.relevance,
  SearchUploadDate date = SearchUploadDate.any,
  SearchDuration duration = SearchDuration.any,
  SearchQuality quality = SearchQuality.any,
}) {
  final filters = <int>[
    if (date != SearchUploadDate.any) ...[0x08, date.code],
    ...switch (type) {
      SearchFilter.videos => [0x10, 1],
      SearchFilter.channels => [0x10, 2],
      SearchFilter.playlists => [0x10, 3],
      SearchFilter.shorts => [0x10, 9],
      SearchFilter.live => [0x40, 1],
      SearchFilter.all => const <int>[],
    },
    if (duration != SearchDuration.any) ...[0x18, duration.code],
    ...quality.bytes,
  ];
  final bytes = <int>[
    if (sort != SearchSort.relevance) ...[0x08, sort.code],
    if (filters.isNotEmpty) ...[0x12, filters.length, ...filters],
  ];
  if (bytes.isEmpty) return null;
  // Escaped twice, as YouTube's own result URLs carry it.
  return base64.encode(bytes).replaceAll('=', '%253D').replaceAll('+', '%252B').replaceAll('/', '%252F');
}
