import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:lumtub/native_http.dart';
import 'package:lumtub/youtube_listing.dart';

void main() {
  test('live playlists', () async {
    for (final client in [http.Client(), appHttpClient()]) {
      final web = YoutubeListing(client);
      final ids = <String>['PLuqpGDexlvGyhwQ4ZpHD17jrcOOWSXSpA'];
      for (final hl in ['en', 'zh-CN', 'it']) {
        await for (final line in web.search('吉尔拉', sp: 'EgIQAw%3D%3D', hl: hl, region: 'IT').take(3)) {
          final m = jsonDecode(line) as Map;
          print('PROBE search hl=$hl ${m['id']} ${m['title']} ${m['url']} ${m['channel']}');
          final id = '${m['id']}';
          if (!ids.contains(id)) ids.add(id);
        }
      }
      for (final id in ids) {
        var n = 0;
        try {
          await for (final _ in web.playlist(id).timeout(const Duration(seconds: 30))) {
            n++;
          }
        } catch (e) {
          print('PROBE error $e');
        }
        print('PROBE ${client.runtimeType} playlist $id lines $n');
      }
    }
  }, timeout: const Timeout(Duration(minutes: 4)));
}
