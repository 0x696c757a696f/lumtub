import 'l10n/l10n.dart';
/// Why a video could not be resolved or played, read from yt-dlp's and
/// libmpv's messages, so each cause is handled its own way instead of all
/// being retried alike.
enum FailureKind {
  /// Members-only: only the channel's members can watch it.
  membersOnly,
  /// Private, removed, region- or age-restricted: retrying
  /// cannot help.
  unavailable,
  /// A live stream or premiere that has not started yet: it plays once it
  /// begins, so Lumtub tries again by itself.
  upcoming,
  /// HTTP 429: more requests only extend the limit.
  rateLimited,
  /// "Sign in to confirm you're not a bot": YouTube distrusts this IP.
  botCheck,
  /// yt-dlp could not solve YouTube's JavaScript challenge; usually an
  /// outdated yt-dlp.
  challenge,
  /// HTTP 403 on a stream: the address expired or lacks a PO Token.
  forbidden,
  /// yt-dlp found no stream the format rules allow (every codec of the
  /// video is disabled, or none is left at the chosen height): retrying with
  /// the same rules cannot help and the rules are never lifted.
  noFormat,
  /// Timeouts, resets, DNS: worth reconnecting.
  network,
  unknown,
}

class PlaybackFailure {
  const PlaybackFailure(this.kind, this.detail, {this.tried = const [], this.disabled = '', this.signedIn = false});

  final FailureKind kind;
  /// The Piped or Invidious servers that were tried after YouTube said 429.
  final List<String> tried;
  /// Names of the codecs the user disabled, for [FailureKind.noFormat].
  final String disabled;
  /// For [FailureKind.membersOnly]: yt-dlp asked with the cookie sign-in.
  final bool signedIn;
  /// The message it was read from.
  final String detail;

  static final _patterns = <(FailureKind, RegExp)>[
    (FailureKind.upcoming, RegExp(r'Premieres in|live event will begin|will begin in|waiting for scheduled stream', caseSensitive: false)),
    (FailureKind.membersOnly, RegExp(r"members.only|join this channel|channel's members", caseSensitive: false)),
    (FailureKind.unavailable, RegExp(
      r"Video unavailable|Private video|video is private|has been removed|"
      r"account[^.]{0,40}terminated|copyright|not available in your country|geo.?restrict|age.?restrict|confirm your age|"
      r"inappropriate|This live stream recording is not available",
      caseSensitive: false,
    )),
    (FailureKind.noFormat, RegExp(r'Requested format is not available', caseSensitive: false)),
    (FailureKind.rateLimited, RegExp(r'\b429\b|Too Many Requests|rate.?limit', caseSensitive: false)),
    (FailureKind.botCheck, RegExp(r"not a bot|confirm you.?re not|Sign in to confirm", caseSensitive: false)),
    (FailureKind.challenge, RegExp(r'n challenge|nsig|signature (solving|extraction|function)|JavaScript runtime|js.?runtime', caseSensitive: false)),
    (FailureKind.forbidden, RegExp(r'\b403\b|Forbidden|PO Token', caseSensitive: false)),
    (FailureKind.network, RegExp(
      r'timed? ?out|connection|tcp|tls|ssl|network|unreachable|getaddrinfo|resolve host|reset by peer|\b5\d\d\b|stream ended',
      caseSensitive: false,
    )),
  ];

  /// The first cause any of [messages] names, most specific first.
  static PlaybackFailure classify(Iterable<String> messages) {
    final given = messages.where((m) => m.trim().isNotEmpty && !isSubtitleError(m)).toList();
    // libmpv's own "Failed to open" says nothing of why; a line before it
    // that does goes first.
    final all = [...given.where((m) => !isBareOpenFailure(m)), ...given.where(isBareOpenFailure)];
    for (final (kind, pattern) in _patterns) {
      final hit = all.where(pattern.hasMatch).firstOrNull;
      if (hit != null) return PlaybackFailure(kind, hit.trim());
    }
    return PlaybackFailure(FailureKind.unknown, all.isEmpty ? '' : all.first.trim());
  }

  /// Whether reopening the video, or resolving it another way, can help.
  bool get retryable => kind == FailureKind.network || kind == FailureKind.forbidden || kind == FailureKind.unknown;

  /// What the watch page shows: the cause and what to do about it.
  String get message {
    final reason = switch (kind) {
      FailureKind.membersOnly => signedIn
          ? tr("This video is for the channel's members only, and the account signed in under Browser sign-in isn't a member")
          : tr("This video is for the channel's members only. If you're a member, sign in under Settings › YouTube account › Browser sign-in to play it"),
      FailureKind.unavailable => tr("This video can't be watched (private, deleted, or region or age restricted)"),
      FailureKind.upcoming => tr("This stream hasn't started yet. It will play as soon as it begins"),
      FailureKind.rateLimited => tried.isEmpty
          ? tr('YouTube is rate-limiting requests (429). Preloading is paused for 10 minutes. Try playing again in a few minutes, or switch proxy nodes.')
          : tr('YouTube is temporarily rate-limiting requests (429), and {0} also failed. Preloading is paused for 10 minutes. Try again in a few minutes or switch proxy node.', [tried.join(tr(', '))]),
      FailureKind.botCheck => tr('YouTube requires a "not a robot" check, meaning the current IP is flagged. Try another proxy node, or choose Piped or Invidious in Settings › Playback › Playback source'),
      FailureKind.challenge => tr("Couldn't solve YouTube's JavaScript challenge, usually because yt-dlp is outdated. Checking for component updates now; restart Lumtub after updating."),
      FailureKind.forbidden => tr('YouTube rejected the video URL (403). Re-parsing still failed. Try another proxy node, or choose Piped or Invidious in Settings › Playback › Playback source'),
      FailureKind.noFormat => disabled.isEmpty ? tr('No playable video stream.') : tr('No playable video stream matches the format rules (disabled: {0}). You can change this under Settings → Video settings.', [disabled]),
      FailureKind.network => tr("Couldn't connect. Check your network or proxy."),
      FailureKind.unknown => isBareOpenFailure(detail) ? tr("The player couldn't open the video stream, and gave no reason. Settings › Network › Network check shows which part is blocked.") : '',
    };
    if (kind == FailureKind.upcoming) return reason;
    // The servers named in the 429 message are said here for the others.
    final servers = tried.isEmpty || kind == FailureKind.rateLimited ? '' : tr(' (also tried {0})', [tried.join(tr(', '))]);
    final shown = detail.length > 300 ? '${detail.substring(0, 300)}…' : detail;
    if (reason.isEmpty) return '$shown$servers';
    return shown.isEmpty ? '$reason$servers' : '$reason$servers\n$shown';
  }
}

/// Whether [message] is libmpv saying only that it could not open the
/// video, without an address or a cause.
bool isBareOpenFailure(String message) => RegExp(r'^\s*(failed to open|loading failed)\b[\s.:]*$', caseSensitive: false).hasMatch(message);

/// Whether an mpv error is about a subtitle track (YouTube's timedtext),
/// which never stops the video itself.
bool isSubtitleError(String message) => _subtitleError.hasMatch(message);

final _subtitleError = RegExp(r'/api/timedtext\b|\bsubtitles?\b|\bsub-add\b', caseSensitive: false);

/// FFmpeg's bare HTTP diagnostics do not identify the failed request.
/// Only the later URL-bearing error can attribute it to media or subtitles.
bool isUnattributedHttpError(String message) =>
    !RegExp(r'https?://|edl://', caseSensitive: false).hasMatch(message) &&
    RegExp(r'\b[45]\d\d\b|too many requests|forbidden', caseSensitive: false).hasMatch(message);
