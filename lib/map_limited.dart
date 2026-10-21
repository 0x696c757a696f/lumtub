/// [work] on each of [items], at most [limit] at a time, results in order.
Future<List<R>> mapLimited<T, R>(List<T> items, int limit, Future<R> Function(T item) work) async {
  final results = List<R?>.filled(items.length, null);
  var next = 0;
  Future<void> worker() async {
    while (next < items.length) {
      final i = next++;
      results[i] = await work(items[i]);
    }
  }

  await Future.wait([for (var i = 0; i < limit && i < items.length; i++) worker()]);
  return results.cast<R>();
}
