
import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/models.dart';
import 'package:lumtub/ui/video_aspect.dart';

void main() {
  group('Chapter', () {
    test('reads yt-dlp chapters in order and skips broken entries', () {
      final chapters = Chapter.listFrom([
        {'start_time': 95.5, 'end_time': 300, 'title': ' Second '},
        {'start_time': 0, 'end_time': 95.5, 'title': 'Intro'},
        {'title': 'no start'},
        'junk',
      ]);
      expect(chapters.map((c) => c.title), ['Intro', 'Second']);
      expect(chapters[1].start, const Duration(milliseconds: 95500));
    });

    test('a single chapter is not a chapter list', () {
      expect(Chapter.listFrom([{'start_time': 0, 'title': 'All'}]), isEmpty);
      expect(Chapter.listFrom(null), isEmpty);
    });

    test('finds the chapter a position is in', () {
      final chapters = Chapter.listFrom([
        {'start_time': 10, 'title': 'A'},
        {'start_time': 60, 'title': 'B'},
      ]);
      expect(Chapter.at(chapters, const Duration(seconds: 5)), isNull);
      expect(Chapter.at(chapters, const Duration(seconds: 10))?.title, 'A');
      expect(Chapter.at(chapters, const Duration(minutes: 5))?.title, 'B');
    });

    test('VideoDetails carries chapters', () {
      final details = VideoDetails.fromJson({
        'title': 't',
        'chapters': [
          {'start_time': 0, 'title': 'A'},
          {'start_time': 30, 'title': 'B'},
        ],
      });
      expect(details.chapters, hasLength(2));
    });
  });

  group('videoAspectFor', () {
    test('follows the current video, so a portrait video after a landscape one is not stretched', () {
      expect(videoAspectFor(null, 1920, 1080), closeTo(16 / 9, 0.001));
      expect(videoAspectFor(null, 1080, 1920), closeTo(9 / 16, 0.001));
    });

    test('a forced ratio wins, and an unknown size falls back to 16:9', () {
      expect(videoAspectFor(4 / 3, 1080, 1920), 4 / 3);
      expect(videoAspectFor(null, null, null), 16 / 9);
      expect(videoAspectFor(null, 0, 1920), 16 / 9);
    });
  });
}
