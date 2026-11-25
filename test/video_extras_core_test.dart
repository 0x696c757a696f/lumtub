import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/heatmap.dart';
import 'package:lumtub/native_core.dart';
import 'package:lumtub/storyboard.dart';
import 'package:lumtub/stream_resolver.dart';

/// The storyboard and replay heatmap the core reads with the rest of a
/// video (native/lumtub_core/src/resolved.rs) against the Dart that read
/// them before, on answers made at random.
void main() {
  final random = Random(11);
  T pick<T>(List<T> from) => from[random.nextInt(from.length)];

  Object? number() => pick<Object?>([random.nextInt(400), random.nextInt(400) + 1, 1 + random.nextDouble() * 300, 0, -5, null, '160', random.nextInt(12) + 1]);

  Map<String, dynamic> board() => {
        if (random.nextInt(10) > 0) 'format_id': pick<Object?>(['sb0', 'sb1', 'sb2', 'sb3', 18, 'x']),
        if (random.nextBool()) 'format_note': pick(['storyboard', 'other']),
        'width': number(),
        'height': number(),
        'rows': pick<Object?>([5, 3, 10, 1, 0, 2.5, null]),
        'columns': pick<Object?>([5, 3, 10, 1, 0, 4.0, null]),
        if (random.nextBool()) 'fps': pick<Object?>([0.5, 1, 0.1, 2, 0, -1, 0.333, '1']),
        'fragments': [
          for (var k = random.nextInt(6); k > 0; k--)
            {
              if (random.nextInt(8) > 0) 'url': pick<Object?>(['https://i.ytimg.com/sb/a/M$k.jpg', 5]),
              if (random.nextInt(8) > 0) 'duration': pick<Object?>([50, 10.5, 0, -3, 1e-7, 2.0000005, random.nextDouble() * 100]),
            },
        ],
      };

  Map<String, dynamic> info() => {
        'formats': [for (var k = random.nextInt(6); k > 0; k--) random.nextInt(3) == 0 ? {'format_id': '18', 'height': 360} : board()],
        if (random.nextInt(3) > 0)
          'heatmap': [
            for (var k = random.nextInt(120); k > 0; k--)
              {
                'start_time': pick<Object?>([random.nextInt(600), random.nextDouble() * 600, null]),
                'end_time': pick<Object?>([random.nextInt(600), random.nextDouble() * 600, 600]),
                'value': pick<Object?>([random.nextDouble(), 1.4, -0.2, 0, 1]),
              },
          ],
      };

  String describe(Storyboard? b) => b == null
      ? 'none'
      : '${b.width}x${b.height} ${b.rows}x${b.columns} ${b.interval.inMicroseconds} ${[for (final s in b.sheets) '${s.url}@${s.duration.inMicroseconds}']}';

  test('reads storyboards and heatmaps as the Dart did', () {
    var boards = 0;
    for (var round = 0; round < 3000; round++) {
      final answer = info();
      final text = jsonEncode(answer);
      final video = ResolvedVideo(jsonDecode(text) as Map<String, dynamic>, File('info.json'), 'f', text: text);
      Storyboard? board;
      try {
        board = Storyboard.from(answer);
      } on UnsupportedError {
        continue; // Dart could not round an endless interval; the core leaves the board out.
      }
      // A frame under a pixel wide, kept by the Dart, is left out now.
      if (board != null && (board.width == 0 || board.height == 0 || board.rows == 0 || board.columns == 0)) continue;
      expect(describe(video.storyboard), describe(board), reason: text);
      if (board != null) boards++;
      expect(video.heatmap?.values, Heatmap.from(answer)?.values, reason: text);
    }
    expect(boards, greaterThan(150));
  }, skip: NativeCore.instance == null ? 'needs LUMTUB_CORE_DLL' : null);
}
