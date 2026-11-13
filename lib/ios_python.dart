import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'app_log.dart';
import 'js_challenge_plugin.dart';
import 'native_core.dart';
import 'native_http.dart';

/// yt-dlp on iOS: an iOS app may not start other programs, so the core
/// runs yt-dlp (the zip app) in the app's own process with the Python the
/// app carries, one Python thread per run. [ProcessTree.start] turns every
/// start of a yt-dlp into an [IosPythonProcess].
class IosPython {
  IosPython._(this._bindings, this.bundledYtDlp);

  final _Bindings _bindings;

  /// The yt-dlp that came with the app, to install when none is there.
  final String? bundledYtDlp;

  /// Set once Python is set up; null off iOS or when the app has none.
  static IosPython? current;

  /// Points the core at the app's Python. Python itself starts with the
  /// first run, on a thread of the core's.
  static Future<IosPython?> prepare(String temporary) async {
    if (!Platform.isIOS) return null;
    final core = NativeCore.instance;
    if (core == null) return null;
    final app = File(Platform.resolvedExecutable).parent.path;
    final library = '$app/Frameworks/Python.framework/Python';
    final home = '$app/python';
    if (!File(library).existsSync() || !Directory(home).existsSync()) {
      logWarn('This build carries no Python; streams come from the core alone');
      return null;
    }
    final _Bindings bindings;
    try {
      bindings = _Bindings(core.library);
    } catch (e) {
      logWarn('The core cannot run Python: $e');
      return null;
    }
    // Output comes back on Dart ports, as the core's HTTP answers do.
    if (!NativeHttp.available) return null;
    await Directory(temporary).create(recursive: true);
    // Lumtub's challenge solver (the core's QuickJS) is registered once for
    // every run, not loaded as a plugin by each.
    final plugins = await JsChallengePlugin.install(temporary);
    final solver = plugins == null ? null : [plugins, 'lumtub', 'yt_dlp_plugins', 'extractor', 'lumtub_jsc.py'].join('/');
    final config = utf8.encode(jsonEncode({
      'library': library,
      'home': home,
      'temporary': temporary,
      'environment': {
        'LUMTUB_CORE': '$app/Frameworks/LumtubCore.framework/LumtubCore',
        'SSL_CERT_FILE': '$home/cacert.pem',
        'LUMTUB_EXECUTABLE': Platform.resolvedExecutable,
        if (solver != null) 'LUMTUB_JSC': solver,
      },
    }));
    if (!_withBytes(config, bindings.configure)) return null;
    final bundled = File('$home/yt-dlp');
    return current = IosPython._(bindings, bundled.existsSync() ? bundled.path : null);
  }

  /// Whether [executable] is a yt-dlp to run in Python.
  static bool runs(String executable) => current != null && (executable.endsWith('/yt-dlp') || executable.endsWith('/yt-dlp-bundled'));

  /// Starts the zip app [app] with [arguments]. A proxy the caller put in
  /// [environment] goes back into the arguments: the run shares the app's
  /// environment, and nothing outside the app sees its arguments.
  Process start(String app, List<String> arguments, Map<String, String>? environment) {
    final proxy = environment?['HTTPS_PROXY'] ?? environment?['ALL_PROXY'];
    final argv = [
      if (proxy != null && !arguments.contains('--proxy')) ...['--proxy', proxy],
      ...arguments,
    ];
    final process = IosPythonProcess._(_bindings);
    final request = utf8.encode(jsonEncode({'app': app, 'argv': argv}));
    if (!_withBytes(request, (p, n) => _bindings.start(process._port.sendPort.nativePort, p, n))) {
      process._fail('yt-dlp could not be started in Python');
    }
    return process;
  }

  static bool _withBytes(List<int> bytes, bool Function(Pointer<Uint8>, int) call) {
    final buffer = malloc<Uint8>(bytes.isEmpty ? 1 : bytes.length);
    try {
      buffer.asTypedList(bytes.length).setAll(0, bytes);
      return call(buffer, bytes.length);
    } finally {
      malloc.free(buffer);
    }
  }
}

/// One yt-dlp run in the app's Python, shaped like a [Process].
class IosPythonProcess implements Process {
  IosPythonProcess._(this._bindings) {
    _port.listen(_receive);
  }

  final _Bindings _bindings;
  final _port = ReceivePort('yt-dlp in Python');
  final _out = StreamController<List<int>>();
  final _err = StreamController<List<int>>();
  final _exit = Completer<int>();

  static int _next = 1;

  /// Not a system process: a number of its own, which no process has.
  @override
  final int pid = -(_next++);

  void _receive(Object? message) {
    if (message is! List || message.length < 2) return;
    switch (message[0]) {
      case 1:
        if (!_out.isClosed) _out.add(message[1] as Uint8List);
      case 2:
        if (!_err.isClosed) _err.add(message[1] as Uint8List);
      case 3:
        _finish(message[1] as int);
    }
  }

  void _fail(String error) {
    _err.add(utf8.encode('ERROR: $error\n'));
    _finish(127);
  }

  void _finish(int code) {
    if (_exit.isCompleted) return;
    _port.close();
    unawaited(_out.close());
    unawaited(_err.close());
    _exit.complete(code);
  }

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    if (_exit.isCompleted) return false;
    _bindings.kill(_port.sendPort.nativePort);
    return true;
  }

  @override
  Future<int> get exitCode => _exit.future;
  @override
  Stream<List<int>> get stdout => _out.stream;
  @override
  Stream<List<int>> get stderr => _err.stream;
  @override
  IOSink get stdin => IOSink(StreamController<List<int>>()..stream.listen((_) {}));
}

class _Bindings {
  _Bindings(DynamicLibrary library)
      : configure = library.lookupFunction<Bool Function(Pointer<Uint8>, Size), bool Function(Pointer<Uint8>, int)>('lumtub_py_configure'),
        start = library.lookupFunction<Bool Function(Int64, Pointer<Uint8>, Size), bool Function(int, Pointer<Uint8>, int)>('lumtub_py_start'),
        kill = library.lookupFunction<Void Function(Int64), void Function(int)>('lumtub_py_kill');

  final bool Function(Pointer<Uint8>, int) configure;
  final bool Function(int port, Pointer<Uint8>, int) start;
  final void Function(int port) kill;
}
