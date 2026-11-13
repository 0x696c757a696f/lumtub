import 'dart:io';

/// The user's own folders for videos and pictures.
enum UserFolder { videos, pictures }

/// [kind] of the signed-in user: Videos and Pictures in the Windows
/// profile, Movies and Pictures on macOS, and on Linux the XDG user folders
/// (user-dirs.dirs, translated names included), else ~/Videos and
/// ~/Pictures. Null without a home folder.
String? userFolder(UserFolder kind, {Map<String, String>? environment, bool? windows, bool? mac}) {
  // Android: the shared Movies and Pictures folders, which an app may
  // write its own files to (Android 10 with requestLegacyExternalStorage).
  if (environment == null && windows == null && mac == null && Platform.isAndroid) {
    return '/storage/emulated/0/${kind == UserFolder.videos ? 'Movies' : 'Pictures'}';
  }
  // iOS: the app's own Documents folder, which the Files app shows.
  if (environment == null && windows == null && mac == null && Platform.isIOS) {
    final home = Platform.environment['HOME'];
    if (home == null || home.isEmpty) return null;
    return '$home/Documents/${kind == UserFolder.videos ? 'Videos' : 'Pictures'}';
  }
  final env = environment ?? Platform.environment;
  final isWindows = windows ?? Platform.isWindows;
  final isMac = mac ?? Platform.isMacOS;
  final home = isWindows ? env['USERPROFILE'] : env['HOME'];
  if (home == null || home.trim().isEmpty) return null;
  final separator = isWindows ? r'\' : '/';
  if (isWindows) return '$home$separator${kind == UserFolder.videos ? 'Videos' : 'Pictures'}';
  if (isMac) return '$home/${kind == UserFolder.videos ? 'Movies' : 'Pictures'}';
  final config = env['XDG_CONFIG_HOME']?.trim().isNotEmpty == true ? env['XDG_CONFIG_HOME']! : '$home/.config';
  final named = xdgUserDir(_readOrEmpty('$config/user-dirs.dirs'), kind == UserFolder.videos ? 'VIDEOS' : 'PICTURES', home);
  return named ?? '$home/${kind == UserFolder.videos ? 'Videos' : 'Pictures'}';
}

/// The folder user-dirs.dirs names for XDG_[name]_DIR, with $HOME filled
/// in; null when it is not there or is the home folder itself, which is
/// what the file says for a folder the user removed.
String? xdgUserDir(String file, String name, String home) {
  final line = RegExp('^XDG_${name}_DIR="([^"]*)"', multiLine: true).firstMatch(file);
  if (line == null) return null;
  final path = line.group(1)!.replaceFirst(r'$HOME', home);
  if (!path.startsWith('/')) return null;
  final trimmed = path.endsWith('/') ? path.substring(0, path.length - 1) : path;
  return trimmed == home ? null : trimmed;
}

String _readOrEmpty(String path) {
  try {
    return File(path).readAsStringSync();
  } catch (_) {
    return '';
  }
}
