import 'dart:convert';
import 'dart:isolate';

import 'models.dart';
import 'native_core.dart';
import 'youtube_web_sign_in.dart';

/// The account's own pages on YouTube, read as the website reads them with
/// the browser sign-in: the home feed, watch history, Watch Later, Liked
/// videos, the playlists and the subscribed channels. Each page comes as
/// the lines a [Listing] reads, parsed by the Rust core
/// (native/lumtub_core/src/listing.rs). The pages are asked for in
/// English, which the core reads counts and dates in.
class YoutubeAccountFeed {
  YoutubeAccountFeed(this.signIn);

  final WebInnerTube signIn;

  /// How many days ago each video of the watch history was watched, by id,
  /// as the history page's sections name the days ("Today", "Monday").
  final Map<String, int> historyDays = {};

  static const home = 'FEwhat_to_watch';
  static const history = 'FEhistory';
  static const watchLater = 'VLWL';
  static const liked = 'VLLL';
  static const playlists = 'FEplaylist_aggregation';
  static const channels = 'FEchannels';

  /// The ids of Watch Later and Liked videos, for [PlaylistResult].
  static const watchLaterId = 'WL';
  static const likedId = 'LL';

  /// Whether the account's pages can be read now.
  bool get available => signIn.signedIn && NativeCore.instance != null;

  /// The entries of [browseId], page after page, as listing lines; at most
  /// [pages] pages. Shorts are left out unless [shorts].
  Stream<String> lines(String browseId, {bool shorts = false, int pages = 20}) async* {
    if (NativeCore.instance == null) return;
    var body = <String, Object?>{'browseId': browseId};
    final seen = <String>{};
    final tokens = <String>{};
    // Read afresh, so a row's "Today" is never kept past its day.
    if (browseId == history) historyDays.clear();
    for (var page = 0; page < pages; page++) {
      final answer = await signIn.post('browse', body, hl: 'en');
      if (answer == null) return;
      if (answer.status != 200) throw StateError('YouTube answered ${answer.status} for $browseId');
      final data = await read(answer.body);
      if (data == null) throw StateError('YouTube sent a page that is not JSON for $browseId');
      for (final entry in (data['entries'] as List<dynamic>? ?? const []).whereType<Map<dynamic, dynamic>>()) {
        final id = '${entry['id'] ?? ''}';
        final day = entry.remove('shelf');
        if (!seen.add(id)) continue;
        if (!shorts && '${entry['url'] ?? ''}'.contains('/shorts/')) continue;
        if (browseId == history && day is String) {
          if (daysAgo(day) case final days?) historyDays[id] = days;
        }
        yield jsonEncode(entry);
      }
      final next = data['continuation'];
      if (next is! String || next.isEmpty || !tokens.add(next)) return;
      body = {'continuation': next};
    }
  }

  /// Up to [limit] videos of [browseId].
  Future<List<VideoItem>> videos(String browseId, {int limit = 60, int pages = 3}) async {
    final found = <VideoItem>[];
    await for (final line in lines(browseId, pages: pages)) {
      if (parseListingEntry(line) case final VideoItem item) found.add(item);
      if (found.length >= limit) break;
    }
    return found;
  }

  /// The entries of the account's playlist [playlistId] in YouTube's
  /// order: each video's id and the entry's own id (setVideoId), which
  /// moving it needs.
  Future<List<(String video, String set)>> playlistEntries(String playlistId) async {
    final found = <(String, String)>[];
    await for (final line in lines('VL$playlistId', shorts: true, pages: 100)) {
      final entry = jsonDecode(line);
      if (entry is Map && entry['id'] is String && entry['playlist_set_id'] is String) found.add((entry['id'] as String, entry['playlist_set_id'] as String));
    }
    return found;
  }

  /// The account's own playlists. Watch Later and Liked videos, whose ids
  /// are too short for [PlaylistResult.isValidId], are left out.
  Future<List<PlaylistResult>> accountPlaylists() async {
    final found = <PlaylistResult>[];
    await for (final line in lines(playlists, pages: 5)) {
      if (parseListingEntry(line) case final PlaylistResult list when PlaylistResult.isValidId(list.id)) found.add(list);
    }
    return found;
  }

  /// The channels the account is subscribed to.
  Future<List<ChannelRef>> subscriptions() async {
    final found = <ChannelRef>[];
    await for (final line in lines(channels, pages: 50)) {
      if (parseListingEntry(line) case final ChannelResult channel) {
        found.add(ChannelRef(channel.ref.id, channel.ref.name, channel.avatar ?? channel.ref.avatar));
      }
    }
    return found;
  }

  /// How many days before [now] the English day [label] of a history
  /// section is: "Today", "Yesterday", a weekday of this week, or a date
  /// such as "Nov 12" or "Nov 12, 2025". Null when it reads as none.
  static int? daysAgo(String label, {DateTime? now}) {
    final at = now ?? DateTime.now();
    final today = DateTime(at.year, at.month, at.day);
    final text = label.trim().toLowerCase();
    if (text == 'today') return 0;
    if (text == 'yesterday') return 1;
    final weekday = _weekdays.indexWhere((day) => text == day || text == day.substring(0, 3));
    if (weekday >= 0) {
      final back = (today.weekday - (weekday + 1)) % 7;
      return back == 0 ? 7 : back;
    }
    final date = RegExp(r'^([a-z]{3})[a-z]*\.? (\d{1,2})(?:, (\d{4}))?$').firstMatch(text);
    if (date == null) return null;
    final month = _months.indexOf(date[1]!) + 1;
    if (month == 0) return null;
    var day = DateTime(int.tryParse(date[3] ?? '') ?? today.year, month, int.parse(date[2]!));
    // Without a year it is the last such day, never one ahead.
    if (date[3] == null && day.isAfter(today)) day = DateTime(today.year - 1, month, day.day);
    final back = today.difference(day).inHours;
    return back < 0 ? null : (back / 24).round();
  }

  static const _weekdays = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'];
  static const _months = ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'];

  /// A website `/browse` answer read by the core, on another isolate: a
  /// page runs to a megabyte.
  static Future<Map<String, Object?>?> read(List<int> body) => Isolate.run(() {
        final core = NativeCore.instance;
        if (core == null) return null;
        final text = core.take(core.withBytes(body, core.youtubeListing));
        final data = text == null ? null : jsonDecode(text);
        return data is Map<String, Object?> ? data : null;
      });
}
