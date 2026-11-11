import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/skins/jsonc.dart';
import 'package:lumtub/skins/skin.dart';
import 'package:lumtub/skins/skin_library.dart';

/// Phones, tablets and TVs add skins from a file, and on a TV every skin
/// shows where the remote's focus is.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  setUp(() => temp = Directory.systemTemp.createTempSync('skins'));
  tearDown(() {
    temp.deleteSync(recursive: true);
    Skin.formFactor = 'desktop';
  });

  String skinText(String id) {
    final json = decodeJsonc(File('skins/paper/skin.jsonc').readAsStringSync());
    return jsonEncode({...json as Map<String, Object?>, 'id': id});
  }

  test('a skin.jsonc on its own and a zip of a folder are both added', () async {
    final skins = Directory('${temp.path}/skins');
    await SkinLibrary.instance.load(folder: skins);
    final single = File('${temp.path}/mine.jsonc')..writeAsStringSync(skinText('my-paper'));
    expect(await SkinLibrary.instance.importFile(single.path), 'my-paper');
    expect(SkinLibrary.instance.byId('my-paper'), isNotNull);

    final zip = '${temp.path}/shared.zip';
    File(zip).writeAsBytesSync(_storedZip({
      'shared-skin/skin.jsonc': utf8.encode(skinText('shared-skin')),
      'shared-skin/note.txt': utf8.encode('kept'),
    }));
    expect(await SkinLibrary.instance.importFile(zip), 'shared-skin');
    expect(File('${skins.path}/shared-skin/note.txt').readAsStringSync(), 'kept');
    expect(skins.listSync().map((e) => e.uri.pathSegments.where((s) => s.isNotEmpty).last).toSet(), {'my-paper', 'shared-skin'});

    final wrong = File('${temp.path}/x.jsonc')..writeAsStringSync(skinText('paper'));
    await expectLater(SkinLibrary.instance.importFile(wrong.path), throwsFormatException);
    final empty = File('${temp.path}/y.json')..writeAsStringSync('{}');
    await expectLater(SkinLibrary.instance.importFile(empty.path), throwsFormatException);
    expect(skins.listSync(), hasLength(2));
  });

  test('adding a skin again replaces it, leaving nothing behind', () async {
    final skins = Directory('${temp.path}/skins');
    await SkinLibrary.instance.load(folder: skins);
    final first = File('${temp.path}/a.jsonc')..writeAsStringSync(skinText('again'));
    expect(await SkinLibrary.instance.importFile(first.path), 'again');
    File('${skins.path}/again/old.txt').writeAsStringSync('old');
    expect(await SkinLibrary.instance.importFile(first.path), 'again');
    expect(File('${skins.path}/again/old.txt').existsSync(), isFalse);
    expect(skins.listSync().map((e) => e.uri.pathSegments.where((s) => s.isNotEmpty).last).toList(), ['again']);
    // A replaced skin left over from a failed removal is not listed.
    Directory('${skins.path}/again.replaced-1').createSync();
    File('${skins.path}/again.replaced-1/skin.jsonc').writeAsStringSync(skinText('again'));
    await SkinLibrary.instance.load(folder: skins);
    expect(SkinLibrary.instance.byId('again')?.folder, endsWith('again'));
  });

  test('on a TV a skin without a focused look gets a ring in its accent', () {
    Skin parse() => Skin.parse(decodeJsonc(File('skins/paper/skin.jsonc').readAsStringSync()), folder: 'skins/paper', builtIn: true);
    Skin.formFactor = 'desktop';
    expect(parse().button?.focused, isNull);
    Skin.formFactor = 'tv';
    final skin = parse();
    final focused = skin.button!.forState(focused: true);
    expect(focused.border, skin.colors.accent);
    expect(focused.borderWidth, 3);
  });
}

int _crc32(List<int> bytes) {
  var crc = 0xFFFFFFFF;
  for (final b in bytes) {
    crc ^= b;
    for (var i = 0; i < 8; i++) {
      crc = crc & 1 != 0 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
    }
  }
  return crc ^ 0xFFFFFFFF;
}

/// A zip with its files stored, not compressed.
Uint8List _storedZip(Map<String, List<int>> files) {
  final out = BytesBuilder();
  final central = BytesBuilder();
  ByteData head(int size) => ByteData(size);
  for (final MapEntry(key: name, value: data) in files.entries) {
    final offset = out.length;
    final nameBytes = utf8.encode(name);
    final crc = _crc32(data);
    final local = head(30)
      ..setUint32(0, 0x04034b50, Endian.little)
      ..setUint16(4, 20, Endian.little)
      ..setUint32(14, crc, Endian.little)
      ..setUint32(18, data.length, Endian.little)
      ..setUint32(22, data.length, Endian.little)
      ..setUint16(26, nameBytes.length, Endian.little);
    out..add(local.buffer.asUint8List())..add(nameBytes)..add(data);
    final entry = head(46)
      ..setUint32(0, 0x02014b50, Endian.little)
      ..setUint16(4, 20, Endian.little)
      ..setUint16(6, 20, Endian.little)
      ..setUint32(16, crc, Endian.little)
      ..setUint32(20, data.length, Endian.little)
      ..setUint32(24, data.length, Endian.little)
      ..setUint16(28, nameBytes.length, Endian.little)
      ..setUint32(42, offset, Endian.little);
    central..add(entry.buffer.asUint8List())..add(nameBytes);
  }
  final start = out.length;
  out.add(central.toBytes());
  final end = head(22)
    ..setUint32(0, 0x06054b50, Endian.little)
    ..setUint16(8, files.length, Endian.little)
    ..setUint16(10, files.length, Endian.little)
    ..setUint32(12, central.length, Endian.little)
    ..setUint32(16, start, Endian.little);
  out.add(end.buffer.asUint8List());
  return out.toBytes();
}
