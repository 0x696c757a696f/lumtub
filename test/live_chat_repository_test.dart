import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/live_chat_repository.dart';

void main() {
  test('uses the configured cache and yt-dlp conventions for replay', () {
    final repository = LiveChatRepository(
      'yt-dlp.exe',
      cacheDirectory: 'C:${Platform.pathSeparator}cache',
      deno: 'C:${Platform.pathSeparator}tools${Platform.pathSeparator}deno.exe',
      proxy: () => 'http://127.0.0.1:7890',
    );
    expect(repository.fileFor('abcdefghijk').path, endsWith('cache${Platform.pathSeparator}live-chat${Platform.pathSeparator}abcdefghijk.live_chat.json'));
    expect(repository.arguments('abcdefghijk'), containsAllInOrder([
      '--skip-download',
      '--no-playlist',
      '--cache-dir', 'C:${Platform.pathSeparator}cache',
      '--proxy', 'http://127.0.0.1:7890',
      '--js-runtimes', 'deno:C:${Platform.pathSeparator}tools${Platform.pathSeparator}deno.exe',
      '--write-subs',
      '--no-part',
      '--sub-langs', 'live_chat',
      '--sub-format', 'json',
      '--output', 'C:${Platform.pathSeparator}cache${Platform.pathSeparator}live-chat${Platform.pathSeparator}%(id)s.%(ext)s',
      '--', 'https://www.youtube.com/watch?v=abcdefghijk',
    ]));
  });

  test('a replay leaves no chat file behind once read', () async {
    final dir = await Directory.systemTemp.createTemp('lumtub-chat-');
    addTearDown(() => dir.delete(recursive: true));
    final script = File('${dir.path}/yt-dlp');
    // Writes the chat where --output says, as yt-dlp would.
    await script.writeAsString('#!/bin/sh\nwhile [ "\$1" != "--output" ]; do shift; done\nout=\$(dirname "\$2")\nprintf \'{}\\n\' > "\$out/abcdefghijk.live_chat.json"\n');
    await Process.run('chmod', ['+x', script.path]);
    final repository = LiveChatRepository(script.path, cacheDirectory: dir.path);
    expect(await repository.replay('abcdefghijk'), isEmpty);
    expect(Directory('${dir.path}/live-chat').listSync(), isEmpty);
  }, skip: Platform.isWindows);
}
