import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'app_log.dart';

/// The package this build is, such as `windows-x64-v3`; empty for builds
/// made outside CI, which never update themselves.
const appPackage = String.fromEnvironment('LUMTUB_PACKAGE');

/// When this build's commit was made, from CI.
final appBuilt = DateTime.tryParse(const String.fromEnvironment('LUMTUB_BUILT'));

/// A release newer than the running build.
class AppRelease {
  const AppRelease({required this.version, required this.page, this.asset});
  /// Such as `0.2.1-72ec49d`.
  final String version;
  /// The release's GitHub page.
  final String page;
  /// The installer or portable ZIP for this package, as GitHub lists it.
  final Map<String, dynamic>? asset;
}

/// Whether the release [tag], published at [published], is newer than
/// [current] built at [built]: a higher version number, or the same number
/// from another commit published after this build.
@visibleForTesting
bool isNewerRelease(String current, String tag, {DateTime? published, DateTime? built}) {
  List<int>? numbers(String version) {
    final match = RegExp(r'^v?(\d+)\.(\d+)\.(\d+)').firstMatch(version);
    return match == null ? null : [for (var i = 1; i <= 3; i++) int.parse(match.group(i)!)];
  }

  final have = numbers(current), offered = numbers(tag);
  if (have == null || offered == null) return false;
  for (var i = 0; i < 3; i++) {
    if (offered[i] != have[i]) return offered[i] > have[i];
  }
  final sameCommit = tag.replaceFirst(RegExp('^v'), '') == current;
  return !sameCommit && published != null && built != null && published.isAfter(built);
}

/// Keeps Lumtub up to date without getting in the way: it checks GitHub,
/// downloads the new installer (or the portable ZIP) in the background and
/// verifies it, then installs it once Lumtub closes, so the next start is
/// the new version. [restartNow] does the same at once.
class AppUpdater extends ChangeNotifier {
  AppUpdater({required http.Client client, required Directory directory, required Future<File> Function(Map<String, dynamic> asset, Directory into, void Function(int received, int? total) onProgress) download})
      : _client = client,
        _directory = directory,
        _download = download;

  final http.Client _client;
  /// Where packages are downloaded to.
  final Directory _directory;
  final Future<File> Function(Map<String, dynamic> asset, Directory into, void Function(int received, int? total) onProgress) _download;

  bool checking = false;
  /// The newer release, while there is one.
  AppRelease? available;
  /// 0 to 1 while downloading.
  double? progress;
  /// The verified package, installed when Lumtub closes.
  File? ready;
  String? error;
  Timer? _timer;

  /// The portable package keeps a portable.txt next to lumtub.exe.
  static bool get portable => File('${File(Platform.resolvedExecutable).parent.path}${Platform.pathSeparator}portable.txt').existsSync();

  /// Whether this build can install updates itself.
  static bool get canInstall => Platform.isWindows && appPackage.isNotEmpty && appBuilt != null;

  /// Checks now and then every six hours, downloading what it finds when
  /// [download] says so.
  void start({required bool Function() download}) {
    unawaited(_cleanUp());
    unawaited(check(download: download()));
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(hours: 6), (_) => check(download: download()));
  }

  /// Asks GitHub for the latest release and, with [download], fetches its
  /// package in the background.
  Future<void> check({bool download = false}) async {
    if (checking) return;
    checking = true;
    error = null;
    notifyListeners();
    try {
      final response = await _client.get(
        Uri.https('api.github.com', '/repos/0x696c757a696f/lumtub/releases/latest'),
        headers: {'Accept': 'application/vnd.github+json', 'User-Agent': 'Lumtub/$appVersion'},
      ).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) throw HttpException('GitHub returned HTTP ${response.statusCode}');
      final json = jsonDecode(response.body);
      if (json is! Map<String, dynamic>) throw const FormatException('Invalid GitHub release response');
      final tag = json['tag_name']?.toString() ?? '';
      final published = DateTime.tryParse(json['published_at']?.toString() ?? '');
      final newer = isNewerRelease(appVersion, tag, published: published, built: appBuilt);
      available = newer ? AppRelease(version: tag.replaceFirst(RegExp('^v'), ''), page: json['html_url']?.toString() ?? '', asset: _assetOf(json)) : null;
      if (!newer) ready = null;
      logInfo(newer ? 'Lumtub update available: ${available!.version}' : 'Lumtub is up to date ($appVersion)');
    } catch (e) {
      error = '$e';
      logInfo('Could not check Lumtub updates: $e');
    } finally {
      checking = false;
      notifyListeners();
    }
    if (download) await this.download();
  }

  /// This package's file of [release]: the installer, or the ZIP for the
  /// portable package.
  static Map<String, dynamic>? _assetOf(Map<String, dynamic> release) {
    if (appPackage.isEmpty) return null;
    final suffix = portable ? '_$appPackage.zip' : '_$appPackage-setup.exe';
    for (final asset in (release['assets'] as List? ?? const []).whereType<Map<String, dynamic>>()) {
      if (asset['name']?.toString().endsWith(suffix) ?? false) return asset;
    }
    return null;
  }

  /// Downloads and verifies the available package, in the background.
  Future<void> download() async {
    final asset = available?.asset;
    if (!canInstall || asset == null || progress != null || ready?.path.endsWith(asset['name'].toString()) == true) return;
    progress = 0;
    error = null;
    notifyListeners();
    try {
      final file = await _download(asset, _directory, (received, total) {
        if (total == null || total <= 0) return;
        progress = received / total;
        notifyListeners();
      });
      ready = file;
      logInfo('Lumtub ${available!.version} downloaded; it installs when Lumtub closes');
    } catch (e) {
      error = '$e';
      logInfo('Could not download the Lumtub update: $e');
    } finally {
      progress = null;
      notifyListeners();
    }
  }

  /// Installs the downloaded package once this process has ended, and
  /// starts Lumtub again when [relaunch]. Returns whether it was handed
  /// over.
  Future<bool> install({bool relaunch = false}) async {
    final file = ready;
    if (file == null || !await file.exists()) return false;
    try {
      final script = File('${_directory.path}${Platform.pathSeparator}install-update.ps1');
      await script.writeAsString(updateScript(package: file.path, processId: pid, executable: Platform.resolvedExecutable, portable: file.path.endsWith('.zip'), relaunch: relaunch));
      await Process.start('powershell.exe', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', script.path], mode: ProcessStartMode.detached);
      logInfo('Installing Lumtub ${available?.version ?? ''} after exit');
      ready = null;
      return true;
    } catch (e) {
      logInfo('Could not start the Lumtub update: $e');
      return false;
    }
  }

  /// Removes the packages of updates already installed.
  Future<void> _cleanUp() async {
    try {
      if (!await _directory.exists()) return;
      await for (final entity in _directory.list()) {
        if (entity is File) await entity.delete();
      }
    } catch (e) {
      logInfo('Could not clean the update folder: $e');
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

/// A PowerShell script that waits for Lumtub ([processId]) to end, then
/// runs the installer silently or copies the portable ZIP over the folder
/// of [executable], removes [package], and starts Lumtub again if
/// [relaunch]. What happens is written to update.log next to the package.
@visibleForTesting
String updateScript({required String package, required int processId, required String executable, required bool portable, required bool relaunch}) {
  String quote(String value) => "'${value.replaceAll("'", "''")}'";
  String parent(String path) => path.substring(0, path.lastIndexOf(RegExp(r'[\\/]')).clamp(0, path.length));
  final folder = parent(executable);
  final log = '${parent(package)}\\update.log';
  return [
    r"$ErrorActionPreference = 'Stop'",
    'try {',
    '  Wait-Process -Id $processId -Timeout 120 -ErrorAction SilentlyContinue',
    if (portable) ...[
      r"  $unpacked = Join-Path $env:TEMP ('lumtub-update-' + [guid]::NewGuid())",
      '  Expand-Archive -LiteralPath ${quote(package)} -DestinationPath \$unpacked -Force',
      '  Copy-Item -Path (Join-Path \$unpacked \'*\') -Destination ${quote(folder)} -Recurse -Force',
      r'  Remove-Item -LiteralPath $unpacked -Recurse -Force',
    ] else
      "  \$setup = Start-Process -FilePath ${quote(package)} -ArgumentList '/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART','/CLOSEAPPLICATIONS' -Wait -PassThru\n"
          "  if (\$setup.ExitCode -ne 0) { throw \"Setup exited with \$(\$setup.ExitCode)\" }",
    '  Remove-Item -LiteralPath ${quote(package)} -Force',
    "  \"\$(Get-Date -Format o) updated\" | Out-File -FilePath ${quote(log)} -Append",
    '} catch {',
    "  \"\$(Get-Date -Format o) \$_\" | Out-File -FilePath ${quote(log)} -Append",
    '}',
    if (relaunch) 'Start-Process -FilePath ${quote(executable)}',
  ].join('\r\n');
}
