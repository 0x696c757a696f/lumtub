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
/// archive, a failed CRC check or one over the limits: [maxEntries] files,
/// [maxEntryBytes] unpacked for each and [maxTotalBytes] for all.
Future<List<String>> extractZip(File archive, Directory into, {String? Function(String name)? select, int maxEntries = 20000, int maxEntryBytes = 1 << 30, int maxTotalBytes = 3 << 30}) async {
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
    if (count > maxEntries) throw const FormatException('Too many files in the zip');
    if (dirSize > 16 << 20 || dirSize < count * 46 || dirOffset + dirSize > length) throw const FormatException('Damaged zip directory');
    await raf.setPosition(dirOffset);
    final read = await raf.read(dirSize);
    if (read.length != dirSize) throw const FormatException('Damaged zip directory');
    final directory = ByteData.sublistView(read);
    final bytes = directory.buffer.asUint8List(directory.offsetInBytes, directory.lengthInBytes);
    final written = <String>[];
    final executable = <String>[];
    var p = 0;
    var unpacked = 0;
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
      if (p + 46 + skip > directory.lengthInBytes) throw const FormatException('Damaged zip directory');
      final name = utf8.decode(bytes.sublist(p + 46, p + 46 + nameLength), allowMalformed: true).replaceAll('\\', '/');
      p += 46 + skip;
      if (name.endsWith('/') || (madeOnUnix && mode & 0xF000 != 0 && mode & 0xF000 != 0x8000)) continue;
      final path = select == null ? name : select(name);
      if (path == null) continue;
      final parts = path.split('/');
      if (path.startsWith('/') || parts.any((part) => part.isEmpty || part == '.' || part == '..' || part.contains(':'))) continue;
      if (size > maxEntryBytes || (unpacked += size) > maxTotalBytes) throw const FormatException('The zip unpacks to too much');
      await raf.setPosition(offset);
      final header = await raf.read(30);
      if (header.length != 30) throw const FormatException('Damaged zip entry');
      final local = ByteData.sublistView(header);
      if (local.getUint32(0, Endian.little) != 0x04034b50) throw const FormatException('Damaged zip entry');
      final start = offset + 30 + local.getUint16(26, Endian.little) + local.getUint16(28, Endian.little);
      if (method != 0 && method != 8) throw FormatException('Unsupported zip compression $method');
      if (start + packed > length) throw const FormatException('Damaged zip entry');
      final target = File([into.path, ...parts].join(Platform.pathSeparator));
      await target.parent.create(recursive: true);
      var checksum = 0;
      var total = 0;
      final sink = target.openWrite();
      try {
        Stream<List<int>> data = archive.openRead(start, start + packed);
        if (method == 8) data = data.transform(ZLibDecoder(raw: true));
        await for (final chunk in data) {
          total += chunk.length;
          // A bomb is stopped at the size the archive states, not after it.
          if (total > size) throw FormatException('Zip entry $name is larger than it says');
          checksum = crc32(chunk, checksum);
          sink.add(chunk);
        }
      } catch (_) {
        await sink.close();
        if (await target.exists()) await target.delete();
        rethrow;
      }
      await sink.close();
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
