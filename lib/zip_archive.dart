import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// CRC-32 (zip) of [data], continuing from [crc].
int crc32(List<int> data, [int crc = 0]) {
  crc ^= 0xFFFFFFFF;
  for (final byte in data) {
    crc = _crcTable[(crc ^ byte) & 0xFF] ^ (crc >> 8);
  }
  return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

final _crcTable = List<int>.generate(256, (n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = c & 1 != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
  }
  return c;
});

/// Writes the files of the zip [archive] into [into], each at the path
/// [select] gives for its name (null skips it), or at its own path.
/// Folders, links and paths leaving [into] are skipped; files the archive
/// marks executable are made executable off Windows. Returns the paths
/// written, relative to [into]. Throws a [FormatException] for a damaged
/// archive or a failed CRC check.
Future<List<String>> extractZip(File archive, Directory into, {String? Function(String name)? select}) async {
  final raf = await archive.open();
  try {
    final length = await raf.length();
    final tailStart = length > 65557 ? length - 65557 : 0;
    await raf.setPosition(tailStart);
    final tail = await raf.read(length - tailStart);
    var eocd = -1;
    for (var i = tail.length - 22; i >= 0; i--) {
      if (tail[i] == 0x50 && tail[i + 1] == 0x4b && tail[i + 2] == 5 && tail[i + 3] == 6) {
        eocd = i;
        break;
      }
    }
    if (eocd < 0) throw const FormatException('Not a zip archive');
    final end = ByteData.sublistView(tail, eocd);
    final count = end.getUint16(10, Endian.little);
    final dirSize = end.getUint32(12, Endian.little);
    final dirOffset = end.getUint32(16, Endian.little);
    if (count == 0xFFFF || dirSize == 0xFFFFFFFF || dirOffset == 0xFFFFFFFF) throw const FormatException('Zip64 is not supported');
    await raf.setPosition(dirOffset);
    final directory = ByteData.sublistView(await raf.read(dirSize));
    final bytes = directory.buffer.asUint8List(directory.offsetInBytes, directory.lengthInBytes);
    final written = <String>[];
    final executable = <String>[];
    var p = 0;
    for (var i = 0; i < count; i++) {
      if (p + 46 > directory.lengthInBytes || directory.getUint32(p, Endian.little) != 0x02014b50) throw const FormatException('Damaged zip directory');
      final madeOnUnix = directory.getUint8(p + 5) == 3;
      final method = directory.getUint16(p + 10, Endian.little);
      final crc = directory.getUint32(p + 16, Endian.little);
      final packed = directory.getUint32(p + 20, Endian.little);
      final size = directory.getUint32(p + 24, Endian.little);
      final nameLength = directory.getUint16(p + 28, Endian.little);
      final skip = nameLength + directory.getUint16(p + 30, Endian.little) + directory.getUint16(p + 32, Endian.little);
      final mode = madeOnUnix ? directory.getUint32(p + 38, Endian.little) >> 16 : 0;
      final offset = directory.getUint32(p + 42, Endian.little);
      final name = utf8.decode(bytes.sublist(p + 46, p + 46 + nameLength), allowMalformed: true).replaceAll('\\', '/');
      p += 46 + skip;
      if (name.endsWith('/') || (madeOnUnix && mode & 0xF000 != 0 && mode & 0xF000 != 0x8000)) continue;
      final path = select == null ? name : select(name);
      if (path == null) continue;
      final parts = path.split('/');
      if (path.startsWith('/') || parts.any((part) => part.isEmpty || part == '.' || part == '..' || part.contains(':'))) continue;
      await raf.setPosition(offset);
      final local = ByteData.sublistView(await raf.read(30));
      if (local.getUint32(0, Endian.little) != 0x04034b50) throw const FormatException('Damaged zip entry');
      final start = offset + 30 + local.getUint16(26, Endian.little) + local.getUint16(28, Endian.little);
      if (method != 0 && method != 8) throw FormatException('Unsupported zip compression $method');
      final target = File([into.path, ...parts].join(Platform.pathSeparator));
      await target.parent.create(recursive: true);
      var checksum = 0;
      var total = 0;
      final sink = target.openWrite();
      try {
        Stream<List<int>> data = archive.openRead(start, start + packed);
        if (method == 8) data = data.transform(ZLibDecoder(raw: true));
        await for (final chunk in data) {
          checksum = crc32(chunk, checksum);
          total += chunk.length;
          sink.add(chunk);
        }
      } finally {
        await sink.close();
      }
      if (total != size || checksum != crc) {
        await target.delete();
        throw FormatException('Zip entry $name is damaged');
      }
      written.add(path);
      if (mode & 0x49 != 0) executable.add(target.path);
    }
    if (!Platform.isWindows) {
      for (var i = 0; i < executable.length; i += 200) {
        final batch = executable.sublist(i, i + 200 > executable.length ? executable.length : i + 200);
        final result = await Process.run('chmod', ['+x', ...batch]);
        if (result.exitCode != 0) throw FileSystemException('Could not make files executable: ${result.stderr}');
      }
    }
    return written;
  } finally {
    await raf.close();
  }
}
