/// Orders installed tool folders such as `2026.10.10.233141`,
/// `2026.10.10.233141-dir` (the same release unpacked) and libmpv's
/// `20261018-x86_64-v3` by their numbers, so `2026.9.30` is older than
/// `2026.10.21`. Names that do not start with a version sort last.
int compareVersionFolders(String a, String b) {
  final left = _VersionKey.parse(a);
  final right = _VersionKey.parse(b);
  if (left == null || right == null) {
    if (left != null) return -1;
    if (right != null) return 1;
    return b.compareTo(a);
  }
  return right.compareTo(left) == 0 ? b.compareTo(a) : right.compareTo(left);
}

class _VersionKey implements Comparable<_VersionKey> {
  _VersionKey(this.numbers, this.unpacked, this.v3);
  final List<int> numbers;
  final bool unpacked;
  final bool v3;

  static final _leading = RegExp(r'^v?(\d+(?:\.\d+)*)');

  static _VersionKey? parse(String name) {
    final base = name.split(RegExp(r'[\\/]')).where((part) => part.isNotEmpty).lastOrNull ?? name;
    final match = _leading.firstMatch(base);
    if (match == null) return null;
    final numbers = match.group(1)!.split('.').map(int.tryParse).toList();
    if (numbers.contains(null)) return null;
    final rest = base.substring(match.end);
    return _VersionKey(numbers.cast<int>(), rest.contains('-dir'), rest.contains('-x86_64-v3'));
  }

  /// Positive when this is newer.
  @override
  int compareTo(_VersionKey other) {
    final length = numbers.length > other.numbers.length ? numbers.length : other.numbers.length;
    for (var i = 0; i < length; i++) {
      final order = (i < numbers.length ? numbers[i] : 0).compareTo(i < other.numbers.length ? other.numbers[i] : 0);
      if (order != 0) return order;
    }
    if (unpacked != other.unpacked) return unpacked ? 1 : -1;
    if (v3 != other.v3) return v3 ? 1 : -1;
    return 0;
  }
}
