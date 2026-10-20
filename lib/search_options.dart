import 'dart:convert';

import 'video_repository.dart';

/// How YouTube orders search results.
enum SearchSort {
  relevance('相关度', 0),
  date('上传日期', 2),
  views('观看次数', 3),
  rating('评分', 1);

  const SearchSort(this.label, this.code);
  final String label;
  final int code;
}

enum SearchUploadDate {
  any('不限时间', 0),
  hour('1 小时内', 1),
  today('今天', 2),
  week('本周', 3),
  month('本月', 4),
  year('今年', 5);

  const SearchUploadDate(this.label, this.code);
  final String label;
  final int code;
}

enum SearchDuration {
  any('不限时长', 0),
  short('4 分钟以内', 1),
  medium('4–20 分钟', 3),
  long('20 分钟以上', 2);

  const SearchDuration(this.label, this.code);
  final String label;
  final int code;
}

/// YouTube's `sp` search parameter: a protobuf message, base64-encoded,
/// with the sort order in field 1 and the filters in message field 2
/// (upload date 1, type 2, duration 3, live 8). Null when nothing is set,
/// which YouTube reads as relevance without filters.
String? searchParams({
  SearchFilter type = SearchFilter.all,
  SearchSort sort = SearchSort.relevance,
  SearchUploadDate date = SearchUploadDate.any,
  SearchDuration duration = SearchDuration.any,
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
  ];
  final bytes = <int>[
    if (sort != SearchSort.relevance) ...[0x08, sort.code],
    if (filters.isNotEmpty) ...[0x12, filters.length, ...filters],
  ];
  if (bytes.isEmpty) return null;
  // Escaped twice, as YouTube's own result URLs carry it.
  return base64.encode(bytes).replaceAll('=', '%253D').replaceAll('+', '%252B').replaceAll('/', '%252F');
}
