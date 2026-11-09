import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lumtub/block_list_updates.dart';
import 'package:lumtub/blocked_groups.dart';
import 'package:lumtub/native_core.dart';

void main() {
  late Directory root;
  late Directory data;
  late Directory cache;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('lumtub-lists-');
    data = Directory('${root.path}/data');
    cache = Directory('${root.path}/cache');
    await data.create();
  });

  tearDown(() => root.delete(recursive: true));

  test('the same signature as the kept one fetches nothing more and waits a day', () async {
    final asked = <String>[];
    final client = MockClient((request) async {
      asked.add(request.url.pathSegments.last);
      return http.Response.bytes([1, 2, 3], 200);
    });
    final updates = BlockListUpdates(client: client, data: data, cache: cache, keptSignature: (_) => [1, 2, 3]);
    await updates.check();
    expect(asked, ['lists.json.sig']);
    expect(updates.waiting, isNull);
    await updates.check();
    expect(asked, ['lists.json.sig'], reason: 'checked less than a day ago');
  });

  test('a kept file that is missing or does not verify is fetched again', () async {
    final asked = <String>[];
    final client = MockClient((request) async {
      asked.add(request.url.pathSegments.last);
      return http.Response.bytes([1, 2, 3], 200);
    });
    // A signature file alone, as an older build kept it, is not a kept list.
    await File('${data.path}/lists.json.sig').writeAsBytes([1, 2, 3]);
    final updates = BlockListUpdates(client: client, data: data, cache: cache, keptSignature: (_) => null);
    await updates.check();
    expect(asked, ['lists.json.sig', 'lists.json']);
    expect(updates.waiting, isNull);
  });

  test('a damaged kept file has no signature, so it does not count as up to date', () async {
    if (NativeCore.instance == null) {
      markTestSkipped('needs lumtub_core');
      return;
    }
    await File('${data.path}/lists.signed').writeAsBytes([3, 0, 0, 0, 1, 2, 3, ...utf8.encode('{"version": 99999999999, "lists": []}')]);
    expect(BlockLists.keptSignature(data.path), isNull);
    await File('${data.path}/lists.signed').writeAsBytes([1, 2]);
    expect(BlockLists.keptSignature(data.path), isNull);
  });

  test('a wrongly signed download is refused and nothing is kept', () async {
    if (NativeCore.instance == null) {
      markTestSkipped('needs lumtub_core');
      return;
    }
    final client = MockClient((request) async => request.url.pathSegments.last == 'lists.json.sig'
        ? http.Response.bytes(List.filled(3373, 0), 200)
        : http.Response('{"version": 99999999999, "built": "", "lists": []}', 200));
    final updates = BlockListUpdates(client: client, data: data, cache: cache);
    await updates.check();
    expect(updates.waiting, isNull);
    expect(File('${data.path}/lists.signed').existsSync(), isFalse);
    expect(File('${data.path}/lists-checked').existsSync(), isFalse, reason: 'a failed check is tried again');
  });

  test('an error answer leaves the lists as they are', () async {
    final updates = BlockListUpdates(client: MockClient((_) async => http.Response('', 404)), data: data, cache: cache);
    await updates.check();
    expect(updates.waiting, isNull);
    expect(data.listSync(), isEmpty);
  });
}
