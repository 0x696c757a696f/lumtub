import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'l10n/l10n.dart';
import 'native_core.dart';

/// Encrypts bytes so only the current user can read them back.
abstract class SecretProtector {
  Uint8List protect(Uint8List data);
  Uint8List unprotect(Uint8List data);

  /// DPAPI on Windows, else the native core's vault: a key kept by the
  /// system keyring.
  static SecretProtector forThisSystem() => Platform.isWindows ? DpapiProtector() : VaultProtector();
}

/// The native core's vault (lumtub_vault_seal): AES-256-GCM under a key
/// the Secret Service keyring keeps on Linux, the keychain on macOS. Where
/// there is no keyring only the file's permissions keep it.
class VaultProtector implements SecretProtector {
  static final _magic = ascii.encode('LTVH');

  @override
  Uint8List protect(Uint8List data) {
    final core = NativeCore.instance;
    final sealed = core?.vaultSeal(utf8.decode(data));
    if (sealed == null) throw FileSystemException(tr("Couldn't encrypt the account credentials"));
    return Uint8List.fromList([..._magic, ...ascii.encode(sealed)]);
  }

  @override
  Uint8List unprotect(Uint8List data) {
    if (data.length < _magic.length || !_listEquals(data.sublist(0, _magic.length), _magic)) throw const FormatException('Not a sealed file');
    final plain = NativeCore.instance?.vaultOpen(ascii.decode(data.sublist(_magic.length)));
    if (plain == null) throw FileSystemException(tr("Couldn't decrypt the account credentials"));
    return Uint8List.fromList(utf8.encode(plain));
  }

  static bool _listEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Windows DPAPI (CryptProtectData), tied to the signed-in Windows user. The
/// key is managed by Windows, so nothing secret is stored next to the file.
class DpapiProtector implements SecretProtector {
  static const _uiForbidden = 0x1;
  // Mixed into the key so other programs calling DPAPI for this user cannot
  // decrypt the file without also knowing this value.
  // The app's earlier name; changing it would make saved sign-ins unreadable.
  static final _entropy = utf8.encode('YTPlus account v1');

  @override
  Uint8List protect(Uint8List data) => _run('CryptProtectData', data);

  @override
  Uint8List unprotect(Uint8List data) => _run('CryptUnprotectData', data);

  Uint8List _run(String function, Uint8List data) {
    final crypt = DynamicLibrary.open('crypt32.dll');
    final kernel = DynamicLibrary.open('kernel32.dll');
    final call = crypt.lookupFunction<_CryptNative, _CryptDart>(function);
    final localFree = kernel.lookupFunction<Pointer<Void> Function(Pointer<Void>), Pointer<Void> Function(Pointer<Void>)>('LocalFree');
    return using((arena) {
      final input = arena<_DataBlob>();
      final entropy = arena<_DataBlob>();
      final output = arena<_DataBlob>();
      input.ref
        ..cbData = data.length
        ..pbData = arena<Uint8>(data.isEmpty ? 1 : data.length);
      input.ref.pbData.asTypedList(data.length).setAll(0, data);
      entropy.ref
        ..cbData = _entropy.length
        ..pbData = arena<Uint8>(_entropy.length);
      entropy.ref.pbData.asTypedList(_entropy.length).setAll(0, _entropy);
      if (call(input, nullptr, entropy, nullptr, nullptr, _uiForbidden, output) == 0) {
        throw FileSystemException(tr("Windows couldn't encrypt or decrypt the account credentials"));
      }
      try {
        return Uint8List.fromList(output.ref.pbData.asTypedList(output.ref.cbData));
      } finally {
        localFree(output.ref.pbData.cast());
      }
    });
  }
}

final class _DataBlob extends Struct {
  @Uint32()
  external int cbData;
  external Pointer<Uint8> pbData;
}

typedef _CryptNative = Int32 Function(Pointer<_DataBlob>, Pointer<Utf16>, Pointer<_DataBlob>, Pointer<Void>, Pointer<Void>, Uint32, Pointer<_DataBlob>);
typedef _CryptDart = int Function(Pointer<_DataBlob>, Pointer<Utf16>, Pointer<_DataBlob>, Pointer<Void>, Pointer<Void>, int, Pointer<_DataBlob>);

/// A small JSON object kept encrypted on disk.
class SecureJsonFile {
  SecureJsonFile(this.file, this.protector);
  final File file;
  final SecretProtector protector;

  /// Null when the file is missing or cannot be decrypted, for example after
  /// it was copied from another Windows account.
  Future<Map<String, dynamic>?> read() async {
    try {
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      final protector = this.protector;
      // The keyring may take a while to answer: never on the window's isolate.
      final plain = protector is VaultProtector ? await Isolate.run(() => protector.unprotect(bytes)) : protector.unprotect(bytes);
      final data = jsonDecode(utf8.decode(plain));
      return data is Map<String, dynamic> ? data : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> write(Map<String, dynamic> value) async {
    final temporary = File('${file.path}.tmp');
    final plain = Uint8List.fromList(utf8.encode(jsonEncode(value)));
    final protector = this.protector;
    final sealed = protector is VaultProtector ? await Isolate.run(() => protector.protect(plain)) : protector.protect(plain);
    if (!Platform.isWindows) {
      // Readable by the user alone before anything is in it.
      await temporary.writeAsBytes(const [], flush: true);
      final chmod = await Process.run('chmod', ['600', temporary.path]);
      if (chmod.exitCode != 0) throw FileSystemException('chmod failed: ${chmod.stderr}', temporary.path);
    }
    await temporary.writeAsBytes(sealed, flush: true);
    await temporary.rename(file.path);
  }

  Future<void> delete() async {
    if (await file.exists()) await file.delete();
  }
}
