import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'app_log.dart';
import 'native_core.dart';

/// Fetches the block lists the repository publishes on its `lists`
/// release, at most once a day. lumtub_core checks the signature (the
/// app's own update keys) and keeps the file only when it is newer than
/// the lists in use; it is read at the next start.
class BlockListUpdates {
  BlockListUpdates({required http.Client client, required Directory data, required Directory cache})
      : _client = client,
        _data = data,
        _cache = cache;

  final http.Client _client;
  final Directory _data;
  final Directory _cache;
  Timer? _timer;
  bool _checking = false;

  /// The version a download brought in, used from the next start.
  int? waiting;

  static const _base = 'https://github.com/0x696c757a696f/lumtub/releases/download/lists';

  File get _checked => File('${_data.path}${Platform.pathSeparator}lists-checked');

  /// Checks now if a day has passed since the last check, then every few
  /// hours while [wanted] says so.
  void start({required bool Function() wanted}) {
    _timer?.cancel();
    void tick() {
      if (wanted()) unawaited(check());
    }

    tick();
    _timer = Timer.periodic(const Duration(hours: 3), (_) => tick());
  }

  void stop() => _timer?.cancel();

  Future<void> check({bool force = false}) async {
    if (_checking) return;
    _checking = true;
    try {
      if (!force && await _checked.exists() && DateTime.now().difference(await _checked.lastModified()) < const Duration(days: 1)) return;
      final headers = {'User-Agent': 'Lumtub/$appVersion'};
      final signature = await _client.get(Uri.parse('$_base/lists.json.sig'), headers: headers).timeout(const Duration(seconds: 30));
      if (signature.statusCode != 200) throw HttpException('HTTP ${signature.statusCode} for lists.json.sig');
      // The same signature is the same file: nothing more to fetch.
      final kept = File('${_data.path}${Platform.pathSeparator}lists.json.sig');
      if (await kept.exists() && _same(await kept.readAsBytes(), signature.bodyBytes)) {
        logInfo('Block lists are up to date');
      } else {
        final lists = await _client.get(Uri.parse('$_base/lists.json'), headers: headers).timeout(const Duration(minutes: 2));
        if (lists.statusCode != 200) throw HttpException('HTTP ${lists.statusCode} for lists.json');
        await _cache.create(recursive: true);
        final file = File('${_cache.path}${Platform.pathSeparator}lists.json');
        final sig = File('${file.path}.sig');
        await file.writeAsBytes(lists.bodyBytes);
        await sig.writeAsBytes(signature.bodyBytes);
        final ask = jsonEncode({'file': file.path, 'signature': sig.path, 'folder': _data.path});
        // A small file: checking it takes a few milliseconds.
        final core = NativeCore.instance;
        final answer = core?.take(core.withText(ask, core.blockListsTake));
        for (final f in [file, sig]) {
          try {
            await f.delete();
          } catch (_) {}
        }
        final json = answer == null ? null : jsonDecode(answer);
        if (json is! Map<String, dynamic>) throw const FormatException('lumtub_core did not answer');
        if (json['error'] case final String error) throw FormatException(error);
        if (json['newer'] == true) {
          waiting = (json['version'] as num).toInt();
          logInfo('Block lists version $waiting downloaded (${json['lists']} lists, ${json['records']} records); used from the next start');
        } else {
          logInfo('Block lists: the published version ${json['version']} is not newer than the one in use');
        }
      }
      await _data.create(recursive: true);
      await _checked.writeAsString(DateTime.now().toUtc().toIso8601String());
    } catch (e) {
      logWarn('Could not update the block lists: $e');
    } finally {
      _checking = false;
    }
  }

  static bool _same(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
