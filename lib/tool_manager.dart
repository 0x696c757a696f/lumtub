import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class ToolPaths {
  final String mpv;
  final String ytDlp;
  final String? deno;
  const ToolPaths({required this.mpv, required this.ytDlp, this.deno});
  List<String> get executableDirectories => [
        File(mpv).parent.path,
        File(ytDlp).parent.path,
        if (deno != null) File(deno!).parent.path,
      ];
}

/// Downloads GitHub release assets to versioned directories, checks SHA-256,
/// and activates new versions only on a future app launch.
class ToolManager {
  final void Function(String) status;
  ToolManager(this.status);

  late final Directory root;
  final http.Client _client = http.Client();

  Future<void> initialize() async {
    root = Directory('${(await getApplicationSupportDirectory()).path}${Platform.pathSeparator}tools');
    await root.create(recursive: true);
  }

  Future<ToolPaths> ensureReady() async {
    if (!Platform.isWindows) throw UnsupportedError('This prototype currently targets Windows x64.');
    var current = discover();
    if (current?.mpv.isNotEmpty != true) {
      status('首次启动：安装 libmpv（shinchiro x64-v3）…');
      await _installMpv();
    }
    current = discover();
    if (current?.ytDlp.isNotEmpty != true) {
      status('首次启动：安装 yt-dlp…');
      await _installYtDlp();
    }
    // Deno is needed by some YouTube JavaScript challenge paths. Optional at startup.
    if (discover()?.deno == null) {
      try {
        status('安装 YouTube 解析所需的 Deno…');
        await _installDeno();
      } catch (e) {
        status('Deno 暂时不可用，可以稍后从工具更新中重试：$e');
      }
    }
    final ready = discover();
    if (ready == null || ready.mpv.isEmpty || ready.ytDlp.isEmpty) {
      throw StateError('Required components could not be installed.');
    }
    return ready;
  }

  ToolPaths? discover() {
    if (!root.existsSync()) return null;
    final mpv = _findNewest('mpv', 'libmpv-2.dll');
    final yt = _findNewest('yt-dlp', 'yt-dlp.exe');
    final deno = _findNewest('deno', 'deno.exe');
    if (mpv == null && yt == null) return null;
    return ToolPaths(mpv: mpv ?? '', ytDlp: yt ?? '', deno: deno);
  }

  String? _findNewest(String group, String fileName) {
    final parent = Directory('${root.path}${Platform.pathSeparator}$group');
    if (!parent.existsSync()) return null;
    final dirs = parent.listSync().whereType<Directory>().where((d) => !d.path.endsWith('.partial')).toList()
      ..sort((a, b) => b.path.compareTo(a.path));
    for (final folder in dirs) {
      try {
        // Extracted mpv-dev archives may put the DLL in a nested directory.
        for (final item in folder.listSync(recursive: true, followLinks: false)) {
          if (item is File && item.uri.pathSegments.last.toLowerCase() == fileName.toLowerCase()) return item.path;
        }
      } catch (_) {}
    }
    return null;
  }

  Future<void> checkUpdates({bool force = false}) async {
    final stamp = File('${root.path}${Platform.pathSeparator}last_update_check.txt');
    if (!force && await stamp.exists()) {
      final last = DateTime.tryParse((await stamp.readAsString()).trim());
      if (last != null && DateTime.now().difference(last) < const Duration(hours: 24)) return;
    }
    final errors = <String>[];
    for (final task in <(String, Future<void> Function())>[
      ('libmpv', _installMpv), ('yt-dlp', _installYtDlp), ('Deno', _installDeno),
    ]) {
      try {
        status('检查 ${task.$1} 更新…');
        await task.$2();
      } catch (e) {
        errors.add('${task.$1}: $e');
      }
    }
    if (errors.isEmpty) {
      await stamp.writeAsString(DateTime.now().toIso8601String());
      status('更新检查完成。如有新版，重启应用后启用。');
    } else {
      status('部分组件更新失败，现有版本不受影响：${errors.join(' / ')}');
    }
  }

  Future<Map<String, dynamic>> _release(String repository) async {
    final response = await _client.get(
      Uri.parse('https://api.github.com/repos/$repository/releases/latest'),
      headers: {'Accept': 'application/vnd.github+json', 'User-Agent': 'YTPlus-Windows/0.1'},
    ).timeout(const Duration(seconds: 25));
    if (response.statusCode != 200) throw HttpException('GitHub API HTTP ${response.statusCode} for $repository');
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Map<String, dynamic> _asset(Map<String, dynamic> release, bool Function(String) accept) {
    final raw = release['assets'];
    if (raw is! List) throw const FormatException('GitHub release contains no assets');
    for (final obj in raw) {
      if (obj is Map<String, dynamic> && accept(obj['name']?.toString() ?? '')) return obj;
    }
    throw StateError('Matching release asset not found: ${release['tag_name']}');
  }

  Future<File> _downloadVerified(Map<String, dynamic> asset, Directory into) async {
    final assetName = asset['name']?.toString() ?? '';
    final uri = Uri.parse(asset['browser_download_url']?.toString() ?? '');
    if (uri.scheme != 'https' || uri.host != 'github.com' || assetName.isEmpty) {
      throw const FormatException('Untrusted GitHub asset URL');
    }
    final digest = asset['digest']?.toString() ?? '';
    if (!RegExp(r'^sha256:[a-fA-F0-9]{64}$').hasMatch(digest)) {
      throw StateError('No trusted SHA-256 digest for $assetName');
    }
    await into.create(recursive: true);
    final file = File('${into.path}${Platform.pathSeparator}$assetName');
    if (await file.exists() && (await _sha256(file)) == digest.substring(7).toLowerCase()) return file;
    final temp = File('${file.path}.download');
    if (await temp.exists()) await temp.delete();
    try {
      final request = http.Request('GET', uri);
      request.headers['User-Agent'] = 'YTPlus-Windows/0.1';
      final result = await _client.send(request).timeout(const Duration(seconds: 30));
      if (result.statusCode != 200) throw HttpException('Download failed: HTTP ${result.statusCode}');
      final sink = temp.openWrite();
      try {
        await sink.addStream(result.stream.timeout(const Duration(seconds: 90)));
      } finally {
        await sink.close();
      }
      if ((await _sha256(temp)) != digest.substring(7).toLowerCase()) {
        throw const FormatException('SHA-256 verification failed');
      }
      if (await file.exists()) await file.delete();
      await temp.rename(file.path);
      return file;
    } catch (_) {
      if (await temp.exists()) await temp.delete();
      rethrow;
    }
  }

  Future<String> _sha256(File file) async => (await sha256.bind(file.openRead()).first).toString();

  Future<void> _installYtDlp() async {
    final release = await _release('yt-dlp/yt-dlp-nightly-builds');
    final tag = _safeTag(release['tag_name']);
    final dest = Directory('${root.path}${Platform.pathSeparator}yt-dlp${Platform.pathSeparator}$tag');
    if (await File('${dest.path}${Platform.pathSeparator}yt-dlp.exe').exists()) return;
    status('下载 yt-dlp $tag…');
    final asset = _asset(release, (name) => name == 'yt-dlp.exe');
    await _downloadVerified(asset, dest);
  }

  Future<void> _installDeno() async {
    final release = await _release('denoland/deno');
    final tag = _safeTag(release['tag_name']);
    final dest = Directory('${root.path}${Platform.pathSeparator}deno${Platform.pathSeparator}$tag');
    if (await File('${dest.path}${Platform.pathSeparator}deno.exe').exists()) return;
    status('下载 Deno $tag…');
    final asset = _asset(release, (name) => name == 'deno-x86_64-pc-windows-msvc.zip');
    final archive = await _downloadVerified(asset, Directory('${root.path}${Platform.pathSeparator}downloads'));
    final partial = Directory('${dest.path}.partial');
    if (await partial.exists()) await partial.delete(recursive: true);
    await partial.create(recursive: true);
    try {
      await _extract(archive, partial, isSevenZip: false);
      if (!await File('${partial.path}${Platform.pathSeparator}deno.exe').exists()) {
        throw StateError('Deno release did not contain deno.exe');
      }
      await dest.parent.create(recursive: true);
      await partial.rename(dest.path);
    } catch (_) {
      if (await partial.exists()) await partial.delete(recursive: true);
      rethrow;
    }
  }

  Future<void> _installMpv() async {
    final release = await _release('shinchiro/mpv-winbuild-cmake');
    final tag = _safeTag(release['tag_name']);
    final asset = _asset(release, (name) => RegExp(r'^mpv-dev-x86_64-v3-.*\.7z$').hasMatch(name));
    final dest = Directory('${root.path}${Platform.pathSeparator}mpv${Platform.pathSeparator}$tag');
    if (await File('${dest.path}${Platform.pathSeparator}libmpv-2.dll').exists()) return;
    status('下载 shinchiro x86-64-v3 libmpv $tag…');
    final archive = await _downloadVerified(asset, Directory('${root.path}${Platform.pathSeparator}downloads'));
    final partial = Directory('${dest.path}.partial');
    if (await partial.exists()) await partial.delete(recursive: true);
    await partial.create(recursive: true);
    try {
      await _extract(archive, partial, isSevenZip: true);
      final found = partial.listSync(recursive: true).whereType<File>().where((e) => e.uri.pathSegments.last == 'libmpv-2.dll');
      if (found.isEmpty) throw const FormatException('libmpv-2.dll not found in archive');
      await dest.parent.create(recursive: true);
      await partial.rename(dest.path);
    } catch (_) {
      if (await partial.exists()) await partial.delete(recursive: true);
      rethrow;
    }
  }

  String _safeTag(Object? value) {
    final tag = value?.toString() ?? '';
    if (!RegExp(r'^[a-zA-Z0-9._-]{1,100}$').hasMatch(tag)) throw const FormatException('Invalid release tag');
    return tag;
  }

  Future<void> _extract(File archive, Directory into, {required bool isSevenZip}) async {
    // Windows' bundled bsdtar can extract ZIP; some builds can extract 7z too.
    try {
      final result = await Process.run('tar.exe', ['-xf', archive.path, '-C', into.path]);
      if (result.exitCode == 0) return;
    } catch (_) {}
    if (!isSevenZip) throw const ProcessException('tar.exe', [], 'Could not extract downloaded ZIP');
    // 7zr.exe is the tiny official stand-alone .7z decoder (not Electron).
    final decoder = File('${root.path}${Platform.pathSeparator}7zr.exe');
    if (!await decoder.exists()) {
      status('下载 7-Zip 独立解压器…');
      final uri = Uri.parse('https://www.7-zip.org/a/7zr.exe');
      final response = await _client.get(uri).timeout(const Duration(seconds: 40));
      if (response.statusCode != 200 || response.bodyBytes.length < 10000 || response.bodyBytes.length > 2000000) {
        throw StateError('Cannot download official 7zr.exe');
      }
      await decoder.writeAsBytes(response.bodyBytes, flush: true);
    }
    final result = await Process.run(decoder.path, ['x', '-y', '-o${into.path}', archive.path]);
    if (result.exitCode != 0) throw ProcessException(decoder.path, ['x'], result.stderr.toString(), result.exitCode);
  }

  void dispose() => _client.close();
}
