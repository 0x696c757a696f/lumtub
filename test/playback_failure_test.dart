import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/playback_failure.dart';

void main() {
  FailureKind kind(List<String> messages) => PlaybackFailure.classify(messages).kind;

  test('names the cause from yt-dlp and libmpv messages', () {
    expect(kind(['ERROR: [youtube] dQw4w9WgXcQ: Private video. Sign in if you\'ve been granted access']), FailureKind.unavailable);
    expect(kind(['ERROR: [youtube] x: Sign in to confirm your age. This video may be inappropriate']), FailureKind.unavailable);
    expect(kind(["ERROR: [youtube] x: This video is available to this channel's members on level: Fan. Join this channel to get access to members-only content like this video, and other exclusive perks."]), FailureKind.membersOnly);
    expect(PlaybackFailure.classify(['ERROR: [youtube] x: Join this channel to get access to members-only content']).retryable, isFalse);
    expect(const PlaybackFailure(FailureKind.membersOnly, '').message, contains('Browser sign-in'));
    expect(const PlaybackFailure(FailureKind.membersOnly, '', signedIn: true).message, contains("isn't a member"));
    expect(kind(['ERROR: [youtube] x: Sign in to confirm you’re not a bot. Use --cookies-from-browser']), FailureKind.botCheck);
    expect(kind(['ERROR: Unable to download API page: HTTP Error 429: Too Many Requests']), FailureKind.rateLimited);
    expect(kind(['WARNING: [youtube] x: n challenge solving failed: Some formats may be missing']), FailureKind.challenge);
    expect(kind(['Failed to open edl://…', 'HTTP error 403 Forbidden']), FailureKind.forbidden);
    expect(kind(['tcp: Connection reset by peer']), FailureKind.network);
    expect(kind(['Connection terminated unexpectedly']), FailureKind.network);
    expect(kind(['something odd']), FailureKind.unknown);
  });

  test('only retries what a retry can fix, and says what to do', () {
    expect(PlaybackFailure.classify(['HTTP Error 429']).retryable, isFalse);
    expect(PlaybackFailure.classify(['Video unavailable']).retryable, isFalse);
    expect(PlaybackFailure.classify(['403 Forbidden']).retryable, isTrue);
    expect(PlaybackFailure.classify(['timed out']).retryable, isTrue);
    expect(PlaybackFailure.classify(['HTTP Error 429']).message, startsWith('YouTube is rate-limiting requests (429)'));
    expect(PlaybackFailure.classify(['odd']).message, 'odd');
  });

  test('names the disabled codecs when no stream matches the format rules', () {
    final failure = PlaybackFailure.classify(['ERROR: [youtube] x: Requested format is not available. Use --list-formats for a list of available formats']);
    expect(failure.kind, FailureKind.noFormat);
    expect(failure.retryable, isFalse);
    final named = PlaybackFailure(failure.kind, failure.detail, disabled: 'AV1, VP9');
    expect(named.message, startsWith('No playable video stream matches the format rules (disabled: AV1, VP9). You can change this under Settings → Video settings.'));
  });

  test('says which servers were tried after a 429', () {
    final limited = PlaybackFailure.classify(['HTTP Error 429']);
    final tried = PlaybackFailure(limited.kind, limited.detail, tried: const ['Piped', 'Invidious']);
    expect(tried.message, contains('and Piped, Invidious also failed'));
    expect(limited.message, isNot(contains('also failed')));
  });

  test('subtitle rate limits cannot replace the media failure', () {
    final failure = PlaybackFailure.classify([
      'Unable to download video subtitles: HTTP Error 429: Too Many Requests',
      'Failed to open https://www.youtube.com/api/timedtext?v=x: HTTP 429',
      'Failed to open https://rr1.googlevideo.com/videoplayback: HTTP 403 Forbidden',
    ]);
    expect(failure.kind, FailureKind.forbidden);
    expect(failure.detail, contains('googlevideo.com'));
    expect(PlaybackFailure.classify(['Failed to open subtitle: HTTP 429']).kind, FailureKind.unknown);
  });

  test('HTTP diagnostics without request addresses have no media attribution', () {
    expect(isUnattributedHttpError('https: HTTP error 429 Too Many Requests'), isTrue);
    expect(isUnattributedHttpError('HTTP error 403 Forbidden'), isTrue);
    expect(isUnattributedHttpError('Failed to open https://rr1.googlevideo.com/x: HTTP 403'), isFalse);
    expect(isSubtitleError('Failed to open https://www.youtube.com/API/TIMEDTEXT?v=x'), isTrue);
    expect(isSubtitleError('sub-add failed'), isTrue);
    expect(isSubtitleError('Failed to open https://rr1.googlevideo.com/x'), isFalse);
  });

  test('a stream that has not started is waited for, not reported as unavailable', () {
    final soon = PlaybackFailure.classify(['Bad state: ERROR: [youtube] qVho8nf4JQM: This live event will begin in a few moments.']);
    expect(soon.kind, FailureKind.upcoming);
    expect(soon.retryable, isFalse);
    expect(soon.message, "This stream hasn't started yet. It will play as soon as it begins");
    expect(kind(['ERROR: [youtube] x: Premieres in 2 hours']), FailureKind.upcoming);
    expect(kind(['ERROR: [youtube] x: This live event will begin in 3 days.']), FailureKind.upcoming);
    expect(kind(['ERROR: [youtube] x: This live stream recording is not available.']), FailureKind.unavailable);
  });

  test('says which servers were tried after YouTube refused', () {
    const failure = PlaybackFailure(FailureKind.botCheck, 'Sign in to confirm you’re not a bot', tried: ['Piped', 'Invidious']);
    expect(failure.message.split('\n').first, endsWith(' (also tried Piped, Invidious)'));
    expect(const PlaybackFailure(FailureKind.unknown, 'odd', tried: ['Piped']).message, 'odd (also tried Piped)');
  });

  test("libmpv's bare \"Failed to open\" is not called a network failure, and a line naming the cause goes first", () {
    final bare = PlaybackFailure.classify(['Failed to open']);
    expect(bare.kind, FailureKind.unknown);
    expect(bare.message, contains('Network check'));
    final caused = PlaybackFailure.classify(['Failed to open', 'tcp: Connection to tcp://rr1.googlevideo.com:443 failed: Connection refused']);
    expect(caused.kind, FailureKind.network);
    expect(caused.detail, startsWith('tcp: Connection'));
    final other = PlaybackFailure.classify(['Failed to open', 'Could not create device']);
    expect(other.kind, FailureKind.unknown);
    expect(other.detail, 'Could not create device');
    expect(other.message, isNot(contains('Network check')));
  });
}
