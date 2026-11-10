import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/zip_archive.dart';

/// A zip with [entries] (name -> bytes), deflated, written the way zip tools do.
Uint8List _zip(Map<String, List<int>> entries, {bool corruptCrc = false}) {
  final out = BytesBuilder();
  final central = BytesBuilder();
  var count = 0;
  entries.forEach((name, data) {
    final packed = ZLibCodec(raw: true).encode(data);
    final nameBytes = utf8.encode(name);
    final crc = crc32(data) ^ (corruptCrc ? 1 : 0);
    ByteData header(int size) => ByteData(size);
    final local = header(30)
      ..setUint32(0, 0x04034b50, Endian.little)
      ..setUint16(4, 20, Endian.little)
      ..setUint16(8, 8, Endian.little)
      ..setUint32(14, crc, Endian.little)
      ..setUint32(18, packed.length, Endian.little)
      ..setUint32(22, data.length, Endian.little)
      ..setUint16(26, nameBytes.length, Endian.little);
    final offset = out.length;
    out
      ..add(local.buffer.asUint8List())
      ..add(nameBytes)
      ..add(packed);
    final entry = header(46)
      ..setUint32(0, 0x02014b50, Endian.little)
      ..setUint16(4, 20, Endian.little)
      ..setUint16(6, 20, Endian.little)
      ..setUint16(10, 8, Endian.little)
      ..setUint32(16, crc, Endian.little)
      ..setUint32(20, packed.length, Endian.little)
      ..setUint32(24, data.length, Endian.little)
      ..setUint16(28, nameBytes.length, Endian.little)
      ..setUint32(42, offset, Endian.little);
    central
      ..add(entry.buffer.asUint8List())
      ..add(nameBytes);
    count++;
  });
  final dirOffset = out.length;
  out.add(central.toBytes());
  final end = ByteData(22)
    ..setUint32(0, 0x06054b50, Endian.little)
    ..setUint16(8, count, Endian.little)
    ..setUint16(10, count, Endian.little)
    ..setUint32(12, central.length, Endian.little)
    ..setUint32(16, dirOffset, Endian.little);
  out.add(end.buffer.asUint8List());
  return out.toBytes();
}

void main() {
  test('crc32 matches the zip standard', () {
    expect(crc32(utf8.encode('123456789')), 0xCBF43926);
    expect(crc32(utf8.encode('6789'), crc32(utf8.encode('12345'))), 0xCBF43926);
  });

  group('extraction', () {
    late Directory temp;
    setUp(() => temp = Directory.systemTemp.createTempSync('lumtub_zip'));
    tearDown(() => temp.deleteSync(recursive: true));

    final exe = List<int>.generate(5000, (i) => i % 251);

    test('writes each file at its path, or where select puts it, and never outside', () async {
      final archive = File('${temp.path}/a.zip')
        ..writeAsBytesSync(_zip({
          'top/bin/tool.exe': exe,
          'top/README.txt': [1, 2, 3],
          '../evil.dll': [8],
        }));
      final out = Directory('${temp.path}/out')..createSync();
      final written = await extractZip(archive, out);
      expect(written.toSet(), {'top/bin/tool.exe', 'top/README.txt'});
      expect(File('${out.path}/top/bin/tool.exe').readAsBytesSync(), exe);
      expect(File('${temp.path}/evil.dll').existsSync(), isFalse);

      final flat = Directory('${temp.path}/flat')..createSync();
      final picked = await extractZip(archive, flat, select: (name) => name.endsWith('.exe') ? name.split('/').last : null);
      expect(picked, ['tool.exe']);
      expect(flat.listSync().map((e) => e.uri.pathSegments.last), ['tool.exe']);
    });

    test('refuses a damaged entry and a file that is not a zip', () async {
      final bad = File('${temp.path}/bad.zip')..writeAsBytesSync(_zip({'x/bin/tool.exe': exe}, corruptCrc: true));
      final out = Directory('${temp.path}/out')..createSync();
      await expectLater(extractZip(bad, out), throwsFormatException);
      final junk = File('${temp.path}/junk.zip')..writeAsBytesSync(List.filled(100, 7));
      await expectLater(extractZip(junk, out), throwsFormatException);
    });
    test('enforces the entry, size and directory limits', () async {
      final out = Directory('${temp.path}/out')..createSync();
      final two = File('${temp.path}/two.zip')..writeAsBytesSync(_zip({'a': exe, 'b': exe}));
      await expectLater(extractZip(two, out, maxEntries: 1), throwsFormatException);
      await expectLater(extractZip(two, out, maxEntryBytes: 100), throwsFormatException);
      await expectLater(extractZip(two, out, maxTotalBytes: 6000), throwsFormatException);
      expect(await extractZip(two, out, maxTotalBytes: 10000), ['a', 'b']);
    });

    test('stops at the size an entry states', () async {
      final bytes = _zip({'bomb': List.filled(100000, 0)});
      final data = ByteData.sublistView(bytes);
      var at = 0;
      while (data.getUint32(at, Endian.little) != 0x02014b50) {
        at++;
      }
      data.setUint32(at + 24, 10, Endian.little);
      final archive = File('${temp.path}/bomb.zip')..writeAsBytesSync(bytes);
      final out = Directory('${temp.path}/out')..createSync();
      await expectLater(extractZip(archive, out), throwsFormatException);
      expect(File('${out.path}/bomb').existsSync(), isFalse);
    });

    test('refuses names and directories that run past their data', () async {
      final out = Directory('${temp.path}/out')..createSync();
      final bytes = _zip({'name.txt': exe});
      var data = ByteData.sublistView(bytes);
      var at = 0;
      while (data.getUint32(at, Endian.little) != 0x02014b50) {
        at++;
      }
      data.setUint16(at + 28, 60000, Endian.little);
      await expectLater(extractZip(File('${temp.path}/n.zip')..writeAsBytesSync(bytes), out), throwsFormatException);
      final big = _zip({'name.txt': exe});
      data = ByteData.sublistView(big);
      data.setUint32(big.length - 22 + 12, 0x7FFFFFFF, Endian.little);
      await expectLater(extractZip(File('${temp.path}/d.zip')..writeAsBytesSync(big), out), throwsFormatException);
    });
  });
}
