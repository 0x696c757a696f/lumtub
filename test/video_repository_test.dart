import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ytplus/video_repository.dart';

void main() {
  test('requests the second page of results by item range', () {
    final repository = VideoRepository('yt-dlp.exe');
    final arguments = repository.searchArguments('lofi', start: 21);
    expect(arguments, containsAllInOrder(['--playlist-items', '21:40']));
    expect(arguments.last, 'ytsearch40:lofi');
  });

  test('keeps the query after the option terminator', () {
    final arguments = VideoRepository('yt-dlp.exe').searchArguments('--exec calc');
    expect(arguments.sublist(arguments.length - 2), ['--', 'ytsearch20:--exec calc']);
  });

  test('streams results line by line and stops yt-dlp when cancelled', () async {
    if (Platform.isWindows) return;
    final dir = await Directory.systemTemp.createTemp('ytplus_search');
    addTearDown(() => dir.delete(recursive: true));
    final script = File('${dir.path}/fake-yt-dlp');
    await script.writeAsString('#!/bin/sh\n'
        'echo \'{"id":"dQw4w9WgXcQ","title":"One","channel":"A"}\'\n'
        'echo \'not json\'\n'
        'echo \'{"id":"9bZkp7q19f0","title":"Two","channel":"B"}\'\n');
    await Process.run('chmod', ['+x', script.path]);
    final items = await VideoRepository(script.path).search('test').toList();
    expect(items.map((item) => item.id), ['dQw4w9WgXcQ', '9bZkp7q19f0']);
  });

  test('reports yt-dlp errors when the first page is empty', () async {
    if (Platform.isWindows) return;
    final dir = await Directory.systemTemp.createTemp('ytplus_search');
    addTearDown(() => dir.delete(recursive: true));
    final script = File('${dir.path}/fake-yt-dlp');
    await script.writeAsString('#!/bin/sh\necho "ERROR: blocked" >&2\nexit 1\n');
    await Process.run('chmod', ['+x', script.path]);
    expect(VideoRepository(script.path).search('test').toList(), throwsA(isA<StateError>().having((e) => e.message, 'message', 'ERROR: blocked')));
  });
}
