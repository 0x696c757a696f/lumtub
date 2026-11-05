import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/native_core.dart';

Future<bool> _running(int pid) async {
  if (!Platform.isWindows) {
    // A killed process can linger as a zombie until it is reaped.
    final out = await Process.run('ps', ['-o', 'stat=', '-p', '$pid']);
    final state = out.stdout.toString().trim();
    return state.isNotEmpty && !state.startsWith('Z');
  }
  final out = await Process.run('tasklist', ['/FI', 'PID eq $pid', '/NH']);
  return out.stdout.toString().contains('$pid');
}

Future<bool> _goneSoon(int pid) async {
  for (var i = 0; i < 100; i++) {
    if (!await _running(pid)) return true;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  return false;
}

void main() {
  test('without the DLL a process is left as it is', () async {
    if (NativeCore.instance != null) return;
    final process = await ProcessTree.start(Platform.resolvedExecutable, const ['--version']);
    expect(process, isNot(isA<ProcessTree>()));
    await process.exitCode;
  });

  test('the recommendations library is there', () {
    expect(NativeCore.instance, isNotNull, reason: 'build native/lumtub_core and point LUMTUB_CORE_DLL at it');
  });

  // CI builds lumtub_core.dll first and points LUMTUB_CORE_DLL at it.
  test('killing a tree ends the processes it started', () async {
    final process = Platform.isWindows
        ? await ProcessTree.start('powershell.exe', [
            '-NoProfile',
            '-Command',
            r"$p = Start-Process -PassThru -WindowStyle Hidden ping -ArgumentList '-n','60','127.0.0.1'; Write-Output $p.Id; Start-Sleep 60",
          ])
        : await ProcessTree.start('/bin/sh', ['-c', r'sleep 60 & echo $!; wait']);
    expect(process, isA<ProcessTree>());
    final grandchild = int.parse((await process.stdout.transform(utf8.decoder).transform(const LineSplitter()).first).trim());
    expect(await _running(grandchild), isTrue);
    expect(process.kill(), isTrue);
    await process.exitCode;
    expect(await _goneSoon(grandchild), isTrue);
  }, skip: NativeCore.instance == null ? 'lumtub_core.dll is not built' : null, timeout: const Timeout(Duration(seconds: 60)));
}
