import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'app_log.dart';
import 'native_core.dart';

/// The package this build is, such as `windows-x64-v3`; empty for builds
/// made outside CI, which never update themselves.
const appPackage = String.fromEnvironment('LUMTUB_PACKAGE');

/// When this build's commit was made, from CI.
final appBuilt = DateTime.tryParse(const String.fromEnvironment('LUMTUB_BUILT'));

/// A release newer than the running build.
class AppRelease {
  const AppRelease({required this.version, required this.page, this.asset, this.signature});
  /// Such as `0.2.1-72ec49d`.
  final String version;
  /// The release's GitHub page.
  final String page;
  /// The installer or portable ZIP for this package, as GitHub lists it.
  final Map<String, dynamic>? asset;
  /// The asset's `.sig`: Ed25519 and ML-DSA-65 signatures, both required.
  final Map<String, dynamic>? signature;
}

/// Keeps Lumtub up to date without getting in the way: it checks GitHub,
/// downloads the new installer (or the portable ZIP) in the background and
/// verifies its SHA-256 and both of its signatures, then installs it once Lumtub closes, so the next start is
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
  /// A version whose package failed its signature check; it is not
  /// downloaded again, and the settings page sends to GitHub instead.
  String? rejected;
  Timer? _timer;

  /// The portable package keeps a portable.txt next to lumtub.exe.
  static bool get portable => File('${File(Platform.resolvedExecutable).parent.path}${Platform.pathSeparator}portable.txt').existsSync();

  /// Whether this build can install updates itself.
  static bool get canInstall => Platform.isWindows && appPackage.isNotEmpty && appBuilt != null;

  /// Checks now and then every six hours, downloading what it finds when
  /// [download] says so.
  void start({required bool Function() download}) {
    // Cleaning first: it deletes what is in the folder, and the first
    // download writes there.
    unawaited(_cleanUp().then((_) => check(download: download())));
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
      final offer = offerOf(json, current: appVersion, built: appBuilt, package: appPackage, portable: portable);
      available = offer;
      if (offer == null) ready = null;
      logInfo(offer != null ? 'Lumtub update available: ${offer.version}' : 'Lumtub is up to date ($appVersion)');
    } catch (e) {
      error = '$e';
      logInfo('Could not check Lumtub updates: $e');
    } finally {
      checking = false;
      notifyListeners();
    }
    if (download) await this.download();
  }

  /// Downloads and verifies the available package, in the background.
  Future<void> download() async {
    final asset = available?.asset;
    if (!canInstall || asset == null || progress != null || rejected == available!.version || ready?.path.endsWith(asset['name'].toString()) == true) return;
    progress = 0;
    error = null;
    notifyListeners();
    try {
      final file = await _download(asset, _directory, (received, total) {
        if (total == null || total <= 0) return;
        // Whole percents only: each notice rebuilds the app.
        final next = (received * 100 ~/ total) / 100;
        if (next == progress) return;
        progress = next;
        notifyListeners();
      });
      try {
        await _verifySignature(file, asset, available!.signature);
      } on FormatException {
        rejected = available!.version;
        rethrow;
      }
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

  /// Fetches the package's `.sig` and checks it in the native core; deletes
  /// [file] and throws when the signatures do not hold.
  Future<void> _verifySignature(File file, Map<String, dynamic> asset, Map<String, dynamic>? signature) async {
    final name = asset['name'].toString();
    try {
      final uri = Uri.parse(signature?['browser_download_url']?.toString() ?? '');
      if (signature == null || uri.scheme != 'https' || uri.host != 'github.com') throw const FormatException('The update has no signature');
      final response = await _client.get(uri, headers: {'User-Agent': 'Lumtub/$appVersion'}).timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) throw HttpException('Signature download failed: HTTP ${response.statusCode}');
      final sig = File('${file.path}.sig');
      await sig.writeAsBytes(response.bodyBytes);
      final path = file.path, sigPath = sig.path;
      final error = await Isolate.run(() => verifyUpdate(file: path, name: name, signature: sigPath));
      await sig.delete();
      if (error != null) throw FormatException(error);
    } catch (_) {
      if (await file.exists()) await file.delete();
      rethrow;
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
      final text = updateScript(package: file.path, processId: pid, executable: Platform.resolvedExecutable, portable: file.path.endsWith('.zip'), relaunch: relaunch);
      if (text == null) return false;
      await script.writeAsString(text);
      await Process.start('powershell.exe', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', script.path], mode: ProcessStartMode.detached);
      logInfo('Installing Lumtub ${available?.version ?? ''} after exit');
      ready = null;
      return true;
    } catch (e) {
      logInfo('Could not start the Lumtub update: $e');
      return false;
    }
  }

  /// Removes the packages of updates already installed, after logging how
  /// the last install went (update.log, and the installer's own log when
  /// it failed).
  Future<void> _cleanUp() async {
    try {
      if (!await _directory.exists()) return;
      final sep = Platform.pathSeparator;
      final outcome = File('${_directory.path}${sep}update.log');
      if (await outcome.exists()) {
        final lines = (await outcome.readAsLines()).where((line) => line.trim().isNotEmpty).toList();
        final last = lines.isEmpty ? '' : lines.last.trim();
        logInfo('Last Lumtub update: $last');
        if (!last.endsWith(' updated')) {
          final setup = File('${_directory.path}${sep}setup.log');
          if (await setup.exists()) {
            final tail = (await setup.readAsLines(encoding: const Utf8Codec(allowMalformed: true))).reversed.take(8).toList().reversed;
            logInfo('Installer log ends with:\n${tail.join('\n')}');
          }
        }
      }
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

/// The update [release] (GitHub's JSON) offers a build of [current] made at
/// [built]: newer, with the file for [package]. Null when it is not newer or
/// the native core is missing.
AppRelease? offerOf(Map<String, dynamic> release, {required String current, DateTime? built, String package = '', bool portable = false}) {
  final core = NativeCore.instance;
  if (core == null) return null;
  final ask = jsonEncode({'release': release, 'current': current, 'built': built == null ? null : built.millisecondsSinceEpoch ~/ 1000, 'package': package, 'portable': portable});
  final answer = jsonDecode(core.take(core.withText(ask, core.updateOffer)) ?? 'null');
  if (answer is! Map<String, dynamic>) return null;
  return AppRelease(version: answer['version'] as String, page: answer['page'] as String, asset: answer['asset'] as Map<String, dynamic>?, signature: answer['signature'] as Map<String, dynamic>?);
}

/// Why the package [file] (listed as [name]) fails its `.sig` file
/// [signature], or null when both signatures hold. It reads the whole
/// package, so run it on another isolate.
String? verifyUpdate({required String file, required String name, required String signature}) {
  final core = NativeCore.instance;
  if (core == null) return 'The native core is missing';
  final answer = jsonDecode(core.take(core.withText(jsonEncode({'file': file, 'name': name, 'signature': signature}), core.updateVerify)) ?? 'null');
  if (answer is Map && answer['ok'] == true) return null;
  return answer is Map ? '${answer['error']}' : 'Could not check the signature';
}

/// A PowerShell script that waits for Lumtub ([processId]) to end, then runs
/// the installer silently or unpacks the portable ZIP over the folder of
/// [executable], removes [package] and starts Lumtub again if [relaunch].
@visibleForTesting
String? updateScript({required String package, required int processId, required String executable, required bool portable, required bool relaunch}) {
  final core = NativeCore.instance;
  if (core == null) return null;
  final ask = jsonEncode({'package': package, 'processId': processId, 'executable': executable, 'portable': portable, 'relaunch': relaunch});
  return jsonDecode(core.take(core.withText(ask, core.updateScript)) ?? 'null') as String?;
}
