import 'dart:convert';

/// JSON with comments, as skin files are written: `//` and `/* */`
/// comments and trailing commas are allowed. Errors name the line.
Object? decodeJsonc(String source) {
  final out = StringBuffer();
  var i = 0;
  final n = source.length;
  while (i < n) {
    final c = source[i];
    if (c == '"') {
      final start = i++;
      while (i < n && source[i] != '"') {
        if (source[i] == '\\') i++;
        i++;
      }
      i++;
      out.write(source.substring(start, i > n ? n : i));
    } else if (c == '/' && i + 1 < n && source[i + 1] == '/') {
      while (i < n && source[i] != '\n') {
        i++;
      }
    } else if (c == '/' && i + 1 < n && source[i + 1] == '*') {
      final end = source.indexOf('*/', i + 2);
      final stop = end < 0 ? n : end + 2;
      // Newlines are kept so error lines still match the file.
      out.write('\n' * '\n'.allMatches(source.substring(i, stop)).length);
      i = stop;
    } else {
      out.write(c);
      i++;
    }
  }
  final text = _dropTrailingCommas(out.toString());
  try {
    return jsonDecode(text);
  } on FormatException catch (e) {
    final offset = e.offset;
    if (offset == null) rethrow;
    final line = '\n'.allMatches(text.substring(0, offset.clamp(0, text.length))).length + 1;
    throw FormatException('line $line: ${e.message}');
  }
}

String _dropTrailingCommas(String s) {
  final out = StringBuffer();
  var inString = false;
  for (var i = 0; i < s.length; i++) {
    final c = s[i];
    if (inString) {
      if (c == '\\') {
        out.write(c);
        if (++i < s.length) out.write(s[i]);
        continue;
      }
      if (c == '"') inString = false;
    } else if (c == '"') {
      inString = true;
    } else if (c == ',') {
      var j = i + 1;
      while (j < s.length && ' \t\r\n'.contains(s[j])) {
        j++;
      }
      // A space keeps offsets, and so error lines, unchanged.
      if (j < s.length && (s[j] == ']' || s[j] == '}')) {
        out.write(' ');
        continue;
      }
    }
    out.write(c);
  }
  return out.toString();
}
