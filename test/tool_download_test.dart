import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lumtub/app_directories.dart';
import 'package:lumtub/tool_manager.dart';

void main() {
  test('a download GitHub answers with 504 is asked again', () async {
    final temp = await Directory.systemTemp.createTemp('lumtub-tools');
    addTearDown(() => temp.delete(recursive: true));
    final body = utf8.encode('yt-dlp');
    var asked = 0;
    final client = MockClient((request) async {
      asked++;
      return asked < 3 ? http.Response('Gateway Time-out', 504) : http.Response.bytes(body, 200);
    });
    final tools = ToolManager(AppDirectories.at(temp), (a, b) {}, client: client);
    final asset = {
      'name': 'yt-dlp',
      'browser_download_url': 'https://github.com/yt-dlp/yt-dlp/releases/download/1/yt-dlp',
      'digest': 'sha256:${sha256.convert(body)}',
    };
    final file = await tools.downloadVerified(asset, temp, (a, b) {});
    expect(await file.readAsBytes(), body);
    expect(asked, 3);
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('a download that keeps failing gives up with the last answer', () async {
    final temp = await Directory.systemTemp.createTemp('lumtub-tools');
    addTearDown(() => temp.delete(recursive: true));
    var asked = 0;
    final client = MockClient((request) async {
      asked++;
      return http.Response('Not Found', 404);
    });
    final tools = ToolManager(AppDirectories.at(temp), (a, b) {}, client: client);
    final asset = {
      'name': 'yt-dlp',
      'browser_download_url': 'https://github.com/yt-dlp/yt-dlp/releases/download/1/yt-dlp',
      'digest': 'sha256:${'0' * 64}',
    };
    await expectLater(tools.downloadVerified(asset, temp, (a, b) {}), throwsA(isA<HttpException>()));
    expect(asked, 1);
  });
}
