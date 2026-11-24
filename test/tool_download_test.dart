import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lumtub/app_directories.dart';
import 'package:lumtub/system_env.dart';
import 'package:lumtub/tool_manager.dart';

void main() {
  test("Windows' own programs are started by full path", () {
    expect(windowsProgram(r'System32\tar.exe', environment: {'SystemRoot': r'D:\Win\'}), r'D:\Win\System32\tar.exe');
    expect(windowsProgram('explorer.exe', environment: {}), r'C:\Windows\explorer.exe');
    expect(windowsProgram(r'System32\reg.exe', environment: {'SystemRoot': r'.\here'}), r'C:\Windows\System32\reg.exe');
  });

  test('takes only a libmpv-2.dll inside the folder out of a 7z listing', () {
    expect(libmpvMember('include/mpv/client.h\r\nlibmpv.dll.a\r\nlibmpv-2.dll\r\n'), 'libmpv-2.dll');
    expect(libmpvMember('mpv/LIBMPV-2.DLL\n'), 'mpv/LIBMPV-2.DLL');
    expect(libmpvMember('../libmpv-2.dll\nC:/libmpv-2.dll\n/libmpv-2.dll\n'), isNull);
    expect(libmpvMember('mpv.def\n'), isNull);
  });

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
