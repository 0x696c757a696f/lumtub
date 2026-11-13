import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/playback_recovery.dart';

void main() {
  late DateTime now;
  late PlaybackRecovery recovery;
  const resume = Duration(hours: 1, minutes: 16, seconds: 39);

  setUp(() {
    now = DateTime(2026);
    recovery = PlaybackRecovery(maxAttempts: 1, clock: () => now);
    expect(recovery.tryAttempt(position: resume), isTrue);
  });

  bool progress(Duration position, {bool playing = true, bool buffering = false, bool decoded = true, double rate = 1}) =>
      recovery.observeProgress(position, playing: playing, buffering: buffering, decoded: decoded, rate: rate);

  test('reopening and returning to the resume position do not reset attempts', () {
    now = now.add(const Duration(seconds: 1));
    expect(progress(resume), isFalse);
    expect(recovery.awaitingProgress, isTrue);
    expect(recovery.tryAttempt(position: resume), isFalse);
  });

  test('ten seconds of decoded progress resets the recovery budget', () {
    for (var second = 1; second <= 10; second++) {
      now = now.add(const Duration(seconds: 1));
      expect(progress(resume + Duration(seconds: second)), second == 10);
    }
    expect(recovery.awaitingProgress, isFalse);
    expect(recovery.tryAttempt(position: resume + const Duration(seconds: 10)), isTrue);
  });

  test('a seek cannot prove successful playback', () {
    now = now.add(const Duration(milliseconds: 250));
    expect(progress(resume + const Duration(seconds: 30)), isFalse);
    expect(recovery.awaitingProgress, isTrue);
    expect(recovery.tryAttempt(position: resume), isFalse);
  });

  test('paused, buffering and undecoded positions cannot prove recovery', () {
    for (var second = 1; second <= 12; second++) {
      now = now.add(const Duration(seconds: 1));
      expect(progress(resume + Duration(seconds: second), playing: false), isFalse);
    }
    for (var second = 13; second <= 24; second++) {
      now = now.add(const Duration(seconds: 1));
      expect(progress(resume + Duration(seconds: second), buffering: true), isFalse);
    }
    for (var second = 25; second <= 36; second++) {
      now = now.add(const Duration(seconds: 1));
      expect(progress(resume + Duration(seconds: second), decoded: false), isFalse);
    }
    expect(recovery.awaitingProgress, isTrue);
    expect(recovery.tryAttempt(position: resume), isFalse);
  });

  test('slow playback advances without being treated as a stalled recovery', () {
    for (var second = 1; second <= 40; second++) {
      now = now.add(const Duration(seconds: 1));
      expect(progress(resume + Duration(milliseconds: second * 250), rate: .25), second == 40);
      expect(recovery.stalled, isFalse);
    }
  });

  test('position notifications without progress still time out', () {
    now = now.add(PlaybackRecovery.stallTimeout);
    expect(progress(resume), isFalse);
    expect(recovery.stalled, isTrue);
    recovery.reset();
    expect(recovery.awaitingProgress, isFalse);
    expect(recovery.stalled, isFalse);
  });

  group('ResumePoint', () {
    late ResumePoint point;
    setUp(() {
      point = ResumePoint(clock: () => now);
      point.start(Duration.zero);
    });

    void play(int seconds) {
      for (var i = 0; i < seconds; i++) {
        now = now.add(const Duration(seconds: 1));
        point.observe(point.current + const Duration(seconds: 1));
      }
    }

    test('a failed stream jumping to the end resumes where playback was', () {
      play(2);
      now = now.add(const Duration(milliseconds: 200));
      point.observe(const Duration(hours: 1, minutes: 38, seconds: 29));
      now = now.add(const Duration(seconds: 10));
      expect(point.beforeFailure, const Duration(seconds: 2));
    });

    test('long after a jump, the place it went to counts', () {
      play(2);
      point.observe(const Duration(minutes: 30));
      play(20);
      expect(point.beforeFailure, const Duration(minutes: 30, seconds: 20));
    });

    test('normal playback is not a jump', () {
      play(12);
      expect(point.beforeFailure, const Duration(seconds: 12));
    });
  });

  test('tells a lost graphics device from other mpv errors', () {
    expect(PlaybackRecovery.graphicsLost('Mapping hardware decoded surface failed.'), isTrue);
    expect(PlaybackRecovery.graphicsLost('AVHWFramesContext: Could not create the texture (887a0005)'), isTrue);
    expect(PlaybackRecovery.graphicsLost('Could not create the texture (887A0006)'), isTrue);
    expect(PlaybackRecovery.graphicsLost('Failed to allocate hw frames.'), isFalse);
    expect(PlaybackRecovery.graphicsLost('Failure when receiving data from the peer'), isFalse);
  });
  group('settled playback', () {
    late SettledPlayback settled;
    var at = Duration.zero;

    /// Plays [seconds] more in quarter-second steps; whether it settled.
    bool play(int seconds, {Duration ahead = const Duration(seconds: 30), bool decoded = true, bool buffering = false, Duration duration = const Duration(minutes: 10)}) {
      var told = false;
      for (var i = 0; i < seconds * 4; i++) {
        at += const Duration(milliseconds: 250);
        if (settled.observe(at, playing: true, buffering: buffering, decoded: decoded, buffered: at + ahead, duration: duration)) told = true;
      }
      return told;
    }

    setUp(() {
      settled = SettledPlayback();
      at = Duration.zero;
      settled.start();
    });

    test('settles after five seconds of steady playback, once', () {
      expect(play(4), isFalse);
      expect(play(2), isTrue);
      expect(play(10), isFalse);
    });

    test('waits for frames and an unbroken run', () {
      expect(play(10, decoded: false), isFalse);
      expect(play(3), isFalse);
      expect(play(3, buffering: true), isFalse);
      expect(play(4), isFalse);
      expect(play(2), isTrue);
    });

    test('a seek starts the count again', () {
      expect(play(4), isFalse);
      at += const Duration(minutes: 1);
      expect(play(4), isFalse);
      expect(play(2), isTrue);
    });

    test('waits for the buffer to fill unless the video is all in', () {
      expect(play(10, ahead: const Duration(seconds: 3)), isFalse);
      expect(play(1), isTrue);
      settled.start();
      at = Duration.zero;
      expect(play(6, ahead: const Duration(seconds: 3), duration: const Duration(seconds: 7)), isTrue);
    });

    test('a stopped video never settles', () {
      settled.stop();
      expect(play(20), isFalse);
    });
  });
}
