import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/app_directories.dart';
import 'package:lumtub/app_log.dart';
import 'package:lumtub/models.dart';
import 'package:lumtub/video_repository.dart';

void main() {
  late Directory root;
  late AppDirectories directories;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('lumtub_history');
    directories = AppDirectories.at(root);
    await directories.data.create(recursive: true);
    await AppLog.open(directories.logs);
  });
  tearDown(() async {
    await AppLog.current?.flush();
    AppLog.current = null;
    await root.delete(recursive: true);
  });

  VideoItem video(int i) => VideoItem(id: 'v${i.toString().padLeft(10, '0')}', title: 'Video $i', channel: 'Channel', url: 'https://www.youtube.com/watch?v=$i');

  Future<HistoryStore> open() async {
    final store = HistoryStore(directories);
    await store.initialize();
    return store;
  }

  test('keeps a thousand videos across a restart', () async {
    final store = await open();
    for (var i = 0; i < 1000; i++) {
      await store.record(video(i));
    }
    await store.flush();
    final again = await open();
    expect(again.items.length, 1000);
    expect(again.items.first.id, video(999).id);
    expect(again.items.last.id, video(0).id);
  });

  test('records close together are written by flush', () async {
    final store = await open();
    unawaited(store.record(video(1)));
    unawaited(store.record(video(2)));
    await store.flush();
    final stored = jsonDecode(await store.file.readAsString()) as List;
    expect(stored.map((e) => (e as Map)['id']), [video(2).id, video(1).id]);
  });

  test('recording the same video again moves it to the front once', () async {
    final store = await open();
    await store.record(video(1));
    await store.record(video(2));
    await store.record(video(1));
    expect(store.items.map((e) => e.id), [video(1).id, video(2).id]);
  });

  test('the history is trimmed to the limit, oldest first', () async {
    final store = await open();
    for (var i = 0; i < historyLimit + 10; i++) {
      await store.record(video(i));
    }
    expect(store.items.length, historyLimit);
    expect(store.items.first.id, video(historyLimit + 9).id);
    expect(store.items.last.id, video(10).id);
    await store.flush();
    expect((await open()).items.length, historyLimit);
  });

  test('a file longer than the limit is trimmed on start', () async {
    final file = File('${directories.data.path}/watch_history.json');
    await file.writeAsString(jsonEncode([for (var i = 0; i < historyLimit + 20; i++) video(i).toJson()]));
    final store = await open();
    expect(store.items.length, historyLimit);
    expect(store.items.first.id, video(0).id);
  });

  test('concurrent records, removals and live updates leave a whole file', () async {
    final store = await open();
    final jobs = <Future<void>>[];
    for (var i = 0; i < 200; i++) {
      jobs.add(store.record(video(i)));
      if (i % 3 == 0) jobs.add(store.remove({video(i - 1).id}));
      if (i % 5 == 0) jobs.add(store.setLiveStatus({video(i).id: 'was_live'}));
    }
    await Future.wait(jobs);
    await store.flush();
    final stored = jsonDecode(await store.file.readAsString()) as List;
    expect(stored.map((e) => (e as Map)['id']).toList(), store.items.map((e) => e.id).toList());
    expect(File('${store.file.path}.tmp').existsSync(), isFalse);
    final again = await open();
    expect(again.items.map((e) => e.id).toList(), store.items.map((e) => e.id).toList());
  });

  test('clear empties the file at once', () async {
    final store = await open();
    await store.record(video(1));
    await store.clear();
    expect(jsonDecode(await store.file.readAsString()), isEmpty);
  });

  test('a corrupt file is kept as .broken, the history starts empty and the failure is logged', () async {
    final file = File('${directories.data.path}/watch_history.json');
    await file.writeAsString('[{"id": "abc", "ti');
    final store = await open();
    expect(store.items, isEmpty);
    expect(File('${file.path}.broken').readAsStringSync(), '[{"id": "abc", "ti');
    await AppLog.current!.flush();
    expect(await AppLog.current!.file.readAsString(), contains('watch_history.json could not be read'));
    await store.record(video(1));
    await store.flush();
    expect((await open()).items.length, 1);
  });
}
