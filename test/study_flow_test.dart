import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/study_flow.dart';
import 'package:lumtub/subtitle_cues.dart';

Duration s(num seconds) => Duration(milliseconds: (seconds * 1000).round());

SubtitleCue cue(num start, num end, String text) => (start: s(start), end: s(end), text: text);

/// Lines of [each] seconds from 0 to [total], a sentence ending every
/// [sentence] lines.
List<SubtitleCue> talk(num total, {num each = 4, int sentence = 3}) => [
      for (var i = 0; i * each < total; i++)
        cue(i * each, i * each + each - 0.2,
            (i + 1) % sentence == 0 ? 'and so it ends.' : 'some words go here'),
    ];

void main() {
  group('studyUnits', () {
    test('cuts about two minutes at sentence ends, covering every line once', () {
      final lines = talk(600);
      final units = studyUnits(lines);
      expect(units.first.first, 0);
      expect(units.last.last, lines.length - 1);
      for (var i = 1; i < units.length; i++) {
        expect(units[i].first, units[i - 1].last + 1);
      }
      for (final unit in units) {
        expect(unit.length.inSeconds, inInclusiveRange(60, 180));
        if (unit != units.last) expect(endsSentence(lines[unit.last].text), isTrue);
      }
      expect(units.length, 5);
    });

    test('a chapter start ends a unit when it falls in range', () {
      final lines = talk(300);
      final units = studyUnits(lines, breaks: [s(0), s(84)]);
      expect(units.first.end, lessThanOrEqualTo(s(84)));
      expect(units[1].start, s(84));
    });

    test('a chapter too short joins the next', () {
      final lines = talk(300);
      final units = studyUnits(lines, breaks: [s(20), s(140)]);
      expect(units.first.start, s(0));
      expect(units.first.end, greaterThan(s(60)));
    });

    test('a short end joins the unit before', () {
      final lines = talk(140);
      final units = studyUnits(lines);
      expect(units, hasLength(1));
      expect(units.single.last, lines.length - 1);
    });

    test('without sentence ends it cuts at the widest gap', () {
      final lines = [
        for (var i = 0; i < 60; i++) cue(i * 4, i * 4 + (i == 25 ? 2 : 3.8), 'no stop here')
      ];
      final units = studyUnits(lines);
      expect(units.first.last, 25);
    });

    test('a shorter length gives more units', () {
      final lines = talk(600);
      expect(studyUnits(lines, target: s(60)).length, greaterThan(studyUnits(lines).length));
    });

    test('unitAt', () {
      final units = studyUnits(talk(600));
      expect(unitAt(units, Duration.zero), 0);
      expect(unitAt(units, units[2].start + s(5)), 2);
      expect(unitAt(units, s(10000)), units.length - 1);
    });
  });

  test('blindEnd stops after 15 s, at 30 s at most', () {
    final lines = talk(300);
    final unit = studyUnits(lines).first;
    expect(blindEnd(lines, unit), lines[3].end);
    final long = [cue(0, 40, 'one very long line.'), cue(40, 100, 'next.'), cue(100, 130, 'end.')];
    expect(blindEnd(long, studyUnits(long).first), s(30));
  });

  group('reverseChunks', () {
    test('grows from the end to the whole line', () {
      final chunks = reverseChunks('I would have gone there if I had known about it');
      expect(chunks.first.text, 'known about it');
      expect(chunks.last.text, 'I would have gone there if I had known about it');
      expect(chunks.last.from, 0);
      for (var i = 1; i < chunks.length; i++) {
        expect(chunks[i].text.length, greaterThan(chunks[i - 1].text.length));
        expect(chunks[i].from, lessThan(chunks[i - 1].from));
      }
      expect(chunks.first.before, 'I would have gone there if I had');
    });

    test('a part starts after a comma when one is near', () {
      final chunks = reverseChunks('When we got there, the shop had already closed for the day');
      expect(chunks.map((c) => c.text), contains('the shop had already closed for the day'));
      expect(chunks.last.from, 0);
    });

    test('a short line is one part', () {
      expect(reverseChunks('Thank you'), [(text: 'Thank you', before: '', from: 0.0)]);
    });

    test('a line without spaces goes by characters', () {
      final chunks = reverseChunks('今天我们来聊一聊这个问题的答案');
      expect(chunks.first.text, '问题的答案'.substring(1));
      expect(chunks.last.text, '今天我们来聊一聊这个问题的答案');
      expect(chunks.length, lessThanOrEqualTo(4));
    });

    test('chunkStart follows the share of the line', () {
      final line = cue(10, 14, 'one two three four five six seven eight');
      final chunks = reverseChunks(line.text);
      final at = chunkStart(line, chunks.first);
      expect(at, greaterThan(s(10)));
      expect(at, lessThan(s(14)));
      expect(chunkStart(line, chunks.last), s(9.92));
    });
  });

  group('StudyRun', () {
    StudyRun run() {
      final lines = talk(300);
      return StudyRun(videoId: 'v', lines: lines, units: studyUnits(lines));
    }

    List<StudyEvent> play(StudyRun run, num from, num to, {num step = 0.2}) {
      final events = <StudyEvent>[];
      for (var t = from; t <= to; t += step) {
        if (run.observe(s(t)) case final event?) events.add(event);
      }
      return events;
    }

    test('blind listening ends after its stretch', () {
      final r = run();
      expect(play(r, 0, 20), [StudyEvent.blindDone]);
    });

    test('a seek of the flow is not a replay', () {
      final r = run()..enter(StudyStep.read);
      play(r, 10, 12);
      r.seeked(to: Duration.zero);
      r.observe(s(12.2));
      r.observe(s(0.1));
      r.observe(s(0.3));
      expect(r.replays, isEmpty);
    });

    test('lines played twice while reading are hard, most replayed first', () {
      final r = run()..enter(StudyStep.read);
      play(r, 0, 9);
      r.observe(s(4));
      play(r, 4.2, 9);
      r.observe(s(4));
      play(r, 4.2, 13);
      r.observe(s(12));
      play(r, 12.2, 15);
      r.observe(s(12));
      play(r, 12.2, 15);
      r.observe(s(12));
      expect(r.hardLines, [3, 1]);
      expect(r.pickShadowLines(), [1, 3]);
      expect(r.toggleHard(s(4.5)), isFalse);
      expect(r.hardLines, [3]);
    });

    test('reading ends at the last line of the unit', () {
      final r = run()..enter(StudyStep.read);
      final last = r.lines[r.current.last];
      expect(play(r, last.start.inMilliseconds / 1000, last.end.inMilliseconds / 1000 + 1),
          [StudyEvent.readDone]);
    });

    test('shadowing without hard lines takes the longest line', () {
      final lines = [
        cue(0, 3, 'short.'),
        cue(3, 8, 'a much longer line than that one.'),
        cue(8, 70, 'end.')
      ];
      final r = StudyRun(videoId: 'v', lines: lines, units: studyUnits(lines))
        ..enter(StudyStep.shadow);
      expect(r.shadowLines, [1]);
      expect(play(r, 3, 8.5), [StudyEvent.chunkDone]);
    });

    test('listening again ends with the unit and then waits for a rating', () {
      final r = run()..enter(StudyStep.relisten);
      final end = r.current.end.inMilliseconds / 1000;
      expect(play(r, end - 2, end + 1), [StudyEvent.relistenDone]);
      r.rating = true;
      expect(play(r, 0, 5), isEmpty);
    });
  });

  test('StudyStore keeps where each video stopped', () async {
    final folder = await Directory.systemTemp.createTemp('study');
    addTearDown(() => folder.delete(recursive: true));
    final file = File('${folder.path}/study.json');
    final store = StudyStore(file)
      ..unitLength = s(90)
      ..slowRate = 0.8
      ..remember('abc', s(120), StudyStep.shadow);
    await store.save();
    final again = StudyStore(file);
    await again.load();
    expect(again.unitLength, s(90));
    expect(again.slowRate, 0.8);
    expect(again.of('abc')?.unitStart, s(120));
    expect(again.of('abc')?.step, StudyStep.shadow);
    again.forget('abc');
    expect(again.of('abc'), isNull);
  });
}
