import 'dart:io';

import 'app_log.dart';
import 'stream_resolver.dart' show MembersCookies;

/// The opt-in way past YouTube's "confirm you're not a bot" check: asking
/// with the browser sign-in's cookies (设置 › 网络, off by default). Shared
/// by playback and downloads, so both count against one hourly limit and
/// both know when this network was last refused.
class BlockedSignIn {
  BlockedSignIn({required this.cookies, required this.enabled, required this.directory});

  /// The cookie sign-in, when there is one.
  final MembersCookies? Function() cookies;

  /// Whether the setting is on.
  final bool Function() enabled;

  /// Where the cookies are written for one yt-dlp run; leftovers a crash
  /// left are wiped with the resolver's (`StreamResolver.deleteStaleInfo`).
  final Directory Function() directory;

  /// At most this many requests an hour go out signed in this way, so an
  /// account is not used for every video of a long session.
  static const perHour = 20;

  /// How long after a refusal a request goes signed in from the start: a
  /// request without the account would only be refused again, which takes
  /// seconds and keeps the address flagged longer.
  static const remember = Duration(minutes: 30);

  DateTime? _blockedAt;
  bool _told = false;

  /// Whether the user is yet to be told that the account got a video
  /// through since this network was refused; once a refusal.
  bool tell() {
    if (_told) return false;
    _told = true;
    return true;
  }

  final _uses = <DateTime>[];

  /// YouTube took this network for a bot.
  void noteBlocked() {
    final again = recentlyBlocked;
    _blockedAt = DateTime.now();
    if (!again) _told = false;
    if (!again) {
      logInfo(
          'YouTube takes this network for a bot; signed-in requests go first for ${remember.inMinutes} minutes when allowed');
    }
  }

  /// A request without the account got through: this network is not
  /// refused any more.
  void noteAnswered() {
    if (_blockedAt == null) return;
    _blockedAt = null;
    logInfo('YouTube answers this network again without the account');
  }

  /// Whether this network was refused within [remember].
  bool get recentlyBlocked {
    final at = _blockedAt;
    return at != null && DateTime.now().difference(at) < remember;
  }

  /// The sign-in, when the setting is on and someone is signed in.
  MembersCookies? get usable {
    if (!enabled()) return null;
    final c = cookies();
    return c != null && c.signedIn ? c : null;
  }

  /// Whether one more signed-in request fits this hour; counts it if so.
  bool take() {
    final now = DateTime.now();
    _uses.removeWhere((at) => now.difference(at) > const Duration(hours: 1));
    if (_uses.length >= perHour) {
      logWarn('Signed-in requests past the bot check are used up for this hour');
      return false;
    }
    _uses.add(now);
    return true;
  }

  /// Uses this hour, for tests.
  int get usedThisHour {
    final now = DateTime.now();
    return _uses.where((at) => now.difference(at) <= const Duration(hours: 1)).length;
  }

  static int _files = 0;

  /// Runs [run] with the sign-in's cookies in a file of their own, wiped as
  /// soon as [run] is done; with null when they cannot be had.
  Future<T> withCookies<T>(String name, Future<T> Function(String? cookies) run) async {
    final c = usable;
    if (c == null) return run(null);
    final dir = directory();
    await dir.create(recursive: true);
    final path = '${dir.path}${Platform.pathSeparator}$name-${_files++}.cookies.txt';
    try {
      if (!await c.writeCookies(path)) {
        logWarn('The cookie sign-in could not be opened for $name');
        return await run(null);
      }
      return await run(path);
    } finally {
      c.wipeCookies(path);
    }
  }
}
