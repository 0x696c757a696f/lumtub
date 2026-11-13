import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lumtub/storyboard.dart';

void main() {
  test('a sheet over the thumbnail size cap is not read to the end', () async {
    var sent = 0;
    Stream<List<int>> pieces() async* {
      for (var i = 0; i < 160; i++) {
        sent++;
        yield List.filled(64 << 10, 1);
      }
    }
    final client = MockClient.streaming((request, _) async => http.StreamedResponse(pieces(), 200));
    expect(await StoryboardSheets(client).sheet('https://i.ytimg.com/sb/x/storyboard3_L2/M0.jpg'), isNull);
    expect(sent, lessThan(160));
  });

  test('a failed sheet is not kept, so it is asked for again', () async {
    var asked = 0;
    final client = MockClient((request) async {
      asked++;
      return http.Response('', 404);
    });
    final sheets = StoryboardSheets(client);
    expect(await sheets.sheet('https://i.ytimg.com/sb/x/M0.jpg'), isNull);
    await Future<void>.delayed(Duration.zero);
    expect(await sheets.sheet('https://i.ytimg.com/sb/x/M0.jpg'), isNull);
    expect(asked, 2);
  });
}
