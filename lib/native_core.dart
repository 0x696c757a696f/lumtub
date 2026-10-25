import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math';

import 'package:ffi/ffi.dart';

import 'app_log.dart';
import 'l10n/l10n.dart';

/// lumtub_core, the Rust library built from native/lumtub_core and
/// shipped next to lumtub.exe. The recommendations, the format policy,
/// the filters (block lists, Shorts, language, bait) and the download
/// dialog's choices need it; without it
/// Lumtub says its install is incomplete (see [missingMessage]).
class NativeCore {
  NativeCore._(DynamicLibrary library)
      : tasteNew = library.lookupFunction<Pointer<Void> Function(Pointer<Uint8>, Size), Pointer<Void> Function(Pointer<Uint8>, int)>('lumtub_taste_new'),
        tasteFinalizer = NativeFinalizer(library.lookup<NativeFinalizerFunction>('lumtub_taste_free')),
        tasteAffinity = library.lookupFunction<Double Function(Pointer<Void>, Pointer<Uint8>, Size), double Function(Pointer<Void>, Pointer<Uint8>, int)>('lumtub_taste_affinity'),
        tasteMatch = library.lookupFunction<Double Function(Pointer<Void>, Pointer<Uint8>, Size), double Function(Pointer<Void>, Pointer<Uint8>, int)>('lumtub_taste_match'),
        tasteInterest = library.lookupFunction<Pointer<Utf8> Function(Pointer<Void>, Pointer<Uint8>, Size), Pointer<Utf8> Function(Pointer<Void>, Pointer<Uint8>, int)>('lumtub_taste_interest'),
        tasteTop = library.lookupFunction<Pointer<Utf8> Function(Pointer<Void>, Bool, Uint32), Pointer<Utf8> Function(Pointer<Void>, bool, int)>('lumtub_taste_top'),
        titleWords = library.lookupFunction<Pointer<Utf8> Function(Pointer<Uint8>, Size), Pointer<Utf8> Function(Pointer<Uint8>, int)>('lumtub_title_words'),
        recommend = library.lookupFunction<Pointer<Utf8> Function(Pointer<Void>, Pointer<Uint8>, Size), Pointer<Utf8> Function(Pointer<Void>, Pointer<Uint8>, int)>('lumtub_recommend'),
        formatPolicy = library.lookupFunction<Pointer<Utf8> Function(Pointer<Uint8>, Size), Pointer<Utf8> Function(Pointer<Uint8>, int)>('lumtub_format_policy'),
        downloadFormats = library.lookupFunction<Pointer<Utf8> Function(Pointer<Uint8>, Size), Pointer<Utf8> Function(Pointer<Uint8>, int)>('lumtub_download_formats'),
        downloadChoose = library.lookupFunction<Pointer<Utf8> Function(Pointer<Uint8>, Size), Pointer<Utf8> Function(Pointer<Uint8>, int)>('lumtub_download_choose'),
        downloadContainer = library.lookupFunction<Pointer<Utf8> Function(Pointer<Uint8>, Size), Pointer<Utf8> Function(Pointer<Uint8>, int)>('lumtub_download_container'),
        updateOffer = library.lookupFunction<Pointer<Utf8> Function(Pointer<Uint8>, Size), Pointer<Utf8> Function(Pointer<Uint8>, int)>('lumtub_update_offer'),
        updateScript = library.lookupFunction<Pointer<Utf8> Function(Pointer<Uint8>, Size), Pointer<Utf8> Function(Pointer<Uint8>, int)>('lumtub_update_script'),
        redact = library.lookupFunction<Pointer<Utf8> Function(Pointer<Uint8>, Size), Pointer<Utf8> Function(Pointer<Uint8>, int)>('lumtub_redact'),
        hashPrefix = library.lookupFunction<Pointer<Utf8> Function(Pointer<Uint8>, Size), Pointer<Utf8> Function(Pointer<Uint8>, int)>('lumtub_hash_prefix'),
        sponsorSegments = library.lookupFunction<Pointer<Utf8> Function(Pointer<Uint8>, Size), Pointer<Utf8> Function(Pointer<Uint8>, int)>('lumtub_sponsor_segments'),
        dearrowBranding = library.lookupFunction<Pointer<Utf8> Function(Pointer<Uint8>, Size), Pointer<Utf8> Function(Pointer<Uint8>, int)>('lumtub_dearrow_branding'),
        fileSha256 = library.lookupFunction<Pointer<Utf8> Function(Pointer<Uint8>, Size), Pointer<Utf8> Function(Pointer<Uint8>, int)>('lumtub_file_sha256'),
        youtubeNext = library.lookupFunction<Pointer<Utf8> Function(Pointer<Uint8>, Size), Pointer<Utf8> Function(Pointer<Uint8>, int)>('lumtub_youtube_next'),
        youtubeComments = library.lookupFunction<Pointer<Utf8> Function(Pointer<Uint8>, Size), Pointer<Utf8> Function(Pointer<Uint8>, int)>('lumtub_youtube_comments'),
        youtubePosts = library.lookupFunction<Pointer<Utf8> Function(Pointer<Uint8>, Size), Pointer<Utf8> Function(Pointer<Uint8>, int)>('lumtub_youtube_posts'),
        liveChat = library.lookupFunction<Pointer<Utf8> Function(Pointer<Uint8>, Size), Pointer<Utf8> Function(Pointer<Uint8>, int)>('lumtub_live_chat'),
        youtubeListing = library.lookupFunction<Pointer<Utf8> Function(Pointer<Uint8>, Size), Pointer<Utf8> Function(Pointer<Uint8>, int)>('lumtub_youtube_listing'),
        hwDecoders = library.lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>('lumtub_hw_decoders'),
        youtubePostComments = library.lookupFunction<Pointer<Utf8> Function(Pointer<Uint8>, Size), Pointer<Utf8> Function(Pointer<Uint8>, int)>('lumtub_youtube_post_comments'),
        titleLanguage = library.lookupFunction<Uint32 Function(Pointer<Uint8>, Size), int Function(Pointer<Uint8>, int)>('lumtub_title_language'),
        looksLikeBait = library.lookupFunction<Bool Function(Pointer<Uint8>, Size), bool Function(Pointer<Uint8>, int)>('lumtub_looks_like_bait'),
        isShort = library.lookupFunction<Bool Function(Pointer<Uint8>, Size), bool Function(Pointer<Uint8>, int)>('lumtub_is_short'),
        blocksNew = library.lookupFunction<Pointer<Void> Function(Pointer<Uint8>, Size), Pointer<Void> Function(Pointer<Uint8>, int)>('lumtub_blocks_new'),
        blocksFinalizer = NativeFinalizer(library.lookup<NativeFinalizerFunction>('lumtub_blocks_free')),
        blocksMatch = library.lookupFunction<Bool Function(Pointer<Void>, Pointer<Uint8>, Size), bool Function(Pointer<Void>, Pointer<Uint8>, int)>('lumtub_blocks_match'),
        _stringFree = library.lookupFunction<Void Function(Pointer<Utf8>), void Function(Pointer<Utf8>)>('lumtub_string_free'),
        _adopt = library.lookupFunction<IntPtr Function(Uint32), int Function(int)>('lumtub_tree_adopt'),
        _kill = library.lookupFunction<Bool Function(IntPtr, Uint32), bool Function(int, int)>('lumtub_tree_kill'),
        _close = library.lookupFunction<Void Function(IntPtr), void Function(int)>('lumtub_tree_close');

  final Pointer<Void> Function(Pointer<Uint8> json, int length) tasteNew;
  /// Frees a taste once Dart no longer holds it.
  final NativeFinalizer tasteFinalizer;
  final double Function(Pointer<Void> taste, Pointer<Uint8> key, int length) tasteAffinity;
  final double Function(Pointer<Void> taste, Pointer<Uint8> title, int length) tasteMatch;
  final Pointer<Utf8> Function(Pointer<Void> taste, Pointer<Uint8> title, int length) tasteInterest;
  final Pointer<Utf8> Function(Pointer<Void> taste, bool words, int count) tasteTop;
  final Pointer<Utf8> Function(Pointer<Uint8> title, int length) titleWords;
  final Pointer<Utf8> Function(Pointer<Void> taste, Pointer<Uint8> json, int length) recommend;
  final Pointer<Utf8> Function(Pointer<Uint8> json, int length) formatPolicy;
  final Pointer<Utf8> Function(Pointer<Uint8> info, int length) downloadFormats;
  final Pointer<Utf8> Function(Pointer<Uint8> json, int length) downloadChoose;
  final Pointer<Utf8> Function(Pointer<Uint8> json, int length) downloadContainer;
  final Pointer<Utf8> Function(Pointer<Uint8> json, int length) updateOffer;
  final Pointer<Utf8> Function(Pointer<Uint8> json, int length) updateScript;
  final Pointer<Utf8> Function(Pointer<Uint8> message, int length) redact;
  /// The first four hex digits of a video id's SHA-256.
  final Pointer<Utf8> Function(Pointer<Uint8> videoId, int length) hashPrefix;
  final Pointer<Utf8> Function(Pointer<Uint8> json, int length) sponsorSegments;
  final Pointer<Utf8> Function(Pointer<Uint8> json, int length) dearrowBranding;
  final Pointer<Utf8> Function(Pointer<Uint8> path, int length) fileSha256;
  /// Related videos and localized text of a YouTube `/next` response.
  final Pointer<Utf8> Function(Pointer<Uint8> body, int length) youtubeNext;
  /// A page of a YouTube comments response.
  final Pointer<Utf8> Function(Pointer<Uint8> body, int length) youtubeComments;
  /// Posts of a browse response or a posts tab's HTML.
  final Pointer<Utf8> Function(Pointer<Uint8> body, int length) youtubePosts;
  /// Chat items of yt-dlp `live_chat` lines.
  final Pointer<Utf8> Function(Pointer<Uint8> lines, int length) liveChat;
  /// Entries and next token of a YouTube search or browse response.
  final Pointer<Utf8> Function(Pointer<Uint8> body, int length) youtubeListing;
  /// The graphics adapter and the tallest picture it decodes per codec.
  final Pointer<Utf8> Function() hwDecoders;
  /// The comment section token of a community post's HTML.
  final Pointer<Utf8> Function(Pointer<Uint8> html, int length) youtubePostComments;
  /// The place in ExploreLanguage of the language a title reads as.
  final int Function(Pointer<Uint8> title, int length) titleLanguage;
  final bool Function(Pointer<Uint8> title, int length) looksLikeBait;
  final bool Function(Pointer<Uint8> json, int length) isShort;
  final Pointer<Void> Function(Pointer<Uint8> json, int length) blocksNew;
  /// Frees block lists once Dart no longer holds them.
  final NativeFinalizer blocksFinalizer;
  final bool Function(Pointer<Void> blocks, Pointer<Uint8> json, int length) blocksMatch;
  final void Function(Pointer<Utf8>) _stringFree;
  final int Function(int pid) _adopt;
  final bool Function(int job, int code) _kill;
  final void Function(int job) _close;

  /// The library, or null when it is not there or too old.
  /// LUMTUB_CORE_DLL points at another copy (tests and `flutter run`).
  static final NativeCore? instance = _load();

  static String get fileName => Platform.isWindows ? 'lumtub_core.dll' : Platform.isMacOS ? 'liblumtub_core.dylib' : 'liblumtub_core.so';

  /// What Lumtub says when the library is missing.
  static String get missingMessage => tr('安装包不完整：缺少 {0}，推荐和屏蔽不可用，画质只能按默认选择。请重新安装 Lumtub。', [fileName]);

  static NativeCore? _load() {
    final paths = [
      if (Platform.environment['LUMTUB_CORE_DLL'] case final path? when path.isNotEmpty) path,
      '${File(Platform.resolvedExecutable).parent.path}${Platform.pathSeparator}$fileName',
    ];
    for (final path in paths) {
      if (!File(path).existsSync()) continue;
      try {
        final core = NativeCore._(DynamicLibrary.open(path));
        AppLog.nativeRedact = (message) => core.take(core.withText(message, core.redact)) ?? message;
        return core;
      } catch (e) {
        logInfo('Could not load $path: $e');
      }
    }
    return null;
  }

  /// The SHA-256 of the file at [path] in hex; null without the core or when
  /// it cannot be read. It blocks, so run it on another isolate.
  static String? fileSha256Of(String path) {
    final core = instance;
    return core?.take(core.withText(path, core.fileSha256));
  }

  /// What the GPU decodes in hardware as JSON; null without the core or
  /// off Windows. It creates a Direct3D device, so run it on another isolate.
  static String? hwDecodersNow() {
    final core = instance;
    return core?.take(core.hwDecoders());
  }

  /// Calls [call] with [text] as UTF-8 in native memory.
  T withText<T>(String text, T Function(Pointer<Uint8> bytes, int length) call) {
    final bytes = utf8.encode(text);
    final buffer = malloc<Uint8>(max(1, bytes.length));
    try {
      buffer.asTypedList(bytes.length).setAll(0, bytes);
      return call(buffer, bytes.length);
    } finally {
      malloc.free(buffer);
    }
  }

  /// The text [value] holds, which it frees; null for a null pointer.
  String? take(Pointer<Utf8> value) {
    if (value == nullptr) return null;
    try {
      return value.toDartString();
    } finally {
      _stringFree(value);
    }
  }
}

/// [process] and everything it starts (yt-dlp's ffmpeg and Deno), kept in
/// a job object: [kill] ends all of them, and whatever is still running
/// when [process] exits, or when Lumtub itself exits or crashes, ends too.
/// Without lumtub_core.dll it is [process] alone.
class ProcessTree implements Process {
  ProcessTree._(this._process, this._job) {
    _process.exitCode.then((_) => _release(), onError: (_) => _release());
  }

  /// Starts [executable] like [Process.start] and puts it in its own tree.
  static Future<Process> start(String executable, List<String> arguments, {Map<String, String>? environment, String? workingDirectory}) async {
    final process = await Process.start(executable, arguments, environment: environment, workingDirectory: workingDirectory);
    return adopt(process);
  }

  /// [process] in a tree of its own, or [process] itself where there is
  /// none (without the DLL, or off Windows).
  static Process adopt(Process process) {
    final core = NativeCore.instance;
    if (core == null) return process;
    final job = core._adopt(process.pid);
    return job == 0 ? process : ProcessTree._(process, job);
  }

  final Process _process;
  int _job;

  void _release() {
    final job = _job;
    if (job == 0) return;
    _job = 0;
    NativeCore.instance?._close(job);
  }

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    final job = _job;
    if (job != 0 && NativeCore.instance!._kill(job, 1)) return true;
    return _process.kill(signal);
  }

  @override
  int get pid => _process.pid;
  @override
  Future<int> get exitCode => _process.exitCode;
  @override
  Stream<List<int>> get stdout => _process.stdout;
  @override
  Stream<List<int>> get stderr => _process.stderr;
  @override
  IOSink get stdin => _process.stdin;
}
