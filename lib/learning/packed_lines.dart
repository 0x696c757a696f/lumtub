import 'dart:convert';
import 'dart:typed_data';

/// A dictionary's lines kept as the file's own UTF-8 bytes, with the
/// keys they are found by in typed lists: a few large objects instead
/// of a string and a list for each of hundreds of thousands of words.
/// The window's isolate shares its heap with the one that reads a
/// dictionary, so every small object made there costs the window frames
/// while the garbage collector copies it.
class PackedLines {
  PackedLines._(this._bytes, this._lineStart, this._lineEnd, this._keyStart, this._keyEnd,
      this._keyLine, this._next, this._table);

  final Uint8List _bytes;
  final Int32List _lineStart;
  final Int32List _lineEnd;

  // One (key, line) pair each; [_next] chains a key's later lines, in
  // file order, from the pair [_table] holds for it.
  final Int32List _keyStart;
  final Int32List _keyEnd;
  final Int32List _keyLine;
  final Int32List _next;

  // Open addressing by the key's hash: the key's first pair + 1, or 0.
  final Int32List _table;

  int get size => _lineStart.length;

  /// Line [i] as text.
  String line(int i) =>
      utf8.decode(Uint8List.sublistView(_bytes, _lineStart[i], _lineEnd[i]), allowMalformed: true);

  /// The lines [key] is found in, in file order; empty when none.
  List<int> linesOf(String key) {
    final first = _find(key);
    if (first < 0) return const [];
    return [for (var p = first; p >= 0; p = _next[p]) _keyLine[p]];
  }

  bool contains(String key) => _find(key) >= 0;

  int _find(String key) {
    final bytes = utf8.encode(key);
    if (bytes.isEmpty || _table.isEmpty) return -1;
    final mask = _table.length - 1;
    for (var slot = _hash(bytes, 0, bytes.length) & mask;; slot = (slot + 1) & mask) {
      final held = _table[slot];
      if (held == 0) return -1;
      final p = held - 1;
      final start = _keyStart[p];
      if (_keyEnd[p] - start != bytes.length) continue;
      var same = true;
      for (var i = 0; i < bytes.length; i++) {
        if (_bytes[start + i] != bytes[i]) {
          same = false;
          break;
        }
      }
      if (same) return p;
    }
  }

  static int _hash(List<int> bytes, int start, int end) {
    var h = 0x811c9dc5;
    for (var i = start; i < end; i++) {
      h = ((h ^ bytes[i]) * 0x01000193) & 0xffffffff;
    }
    return h;
  }

  /// Indexes [bytes] (UTF-8 text) line by line: [keysOf] is given each
  /// line's start and end (without the line break) and calls `key` with
  /// the start and end of each key the line is found by, or nothing to
  /// leave the line out.
  static PackedLines build(Uint8List bytes,
      void Function(int start, int end, void Function(int start, int end) key) keysOf) {
    final lineStart = _Ints();
    final lineEnd = _Ints();
    final keyStart = _Ints();
    final keyEnd = _Ints();
    final keyLine = _Ints();
    var start = 0;
    void addKey(int from, int to) {
      if (to <= from) return;
      if (lineStart.length == 0 || lineStart.last != start) {
        lineStart.add(start);
        lineEnd.add(-1);
      }
      keyStart.add(from);
      keyEnd.add(to);
      keyLine.add(lineStart.length - 1);
    }

    while (start < bytes.length) {
      var end = start;
      while (end < bytes.length && bytes[end] != 0x0a) {
        end++;
      }
      final next = end + 1;
      if (end > start && bytes[end - 1] == 0x0d) end--;
      keysOf(start, end, addKey);
      if (lineStart.length > 0 && lineStart.last == start) lineEnd.setLast(end);
      start = next;
    }

    final pairs = keyLine.length;
    var capacity = 16;
    while (capacity < pairs * 2) {
      capacity <<= 1;
    }
    final table = Int32List(pairs == 0 ? 0 : capacity);
    final next = Int32List(pairs);
    final tail = Int32List(pairs);
    final starts = keyStart.done();
    final ends = keyEnd.done();
    final lines = keyLine.done();
    final mask = capacity - 1;
    for (var p = 0; p < pairs; p++) {
      next[p] = -1;
      final from = starts[p];
      final length = ends[p] - from;
      for (var slot = _hash(bytes, from, ends[p]) & mask;; slot = (slot + 1) & mask) {
        final held = table[slot];
        if (held == 0) {
          table[slot] = p + 1;
          tail[p] = p;
          break;
        }
        final head = held - 1;
        final other = starts[head];
        if (ends[head] - other != length) continue;
        var same = true;
        for (var i = 0; i < length; i++) {
          if (bytes[other + i] != bytes[from + i]) {
            same = false;
            break;
          }
        }
        if (!same) continue;
        final last = tail[head];
        if (lines[last] != lines[p]) {
          next[last] = p;
          tail[head] = p;
        }
        break;
      }
    }
    return PackedLines._(bytes, lineStart.done(), lineEnd.done(), starts, ends, lines, next, table);
  }
}

/// A growing list of 32-bit ints in one typed list.
class _Ints {
  var _list = Int32List(1024);
  int length = 0;

  int get last => _list[length - 1];

  void setLast(int value) => _list[length - 1] = value;

  void add(int value) {
    if (length == _list.length) {
      final bigger = Int32List(_list.length * 2)..setRange(0, length, _list);
      _list = bigger;
    }
    _list[length++] = value;
  }

  /// The ints, in a list of their own size.
  Int32List done() => Int32List(length)..setRange(0, length, _list);
}
