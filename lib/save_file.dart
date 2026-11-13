import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';

/// Asks where to save [bytes] as [name] and writes them there. False when
/// the person cancelled.
///
/// Android and iOS have no save dialog in file_selector, so the system's
/// own document picker is used there.
Future<bool> saveFileAs(String name, Uint8List bytes, {required String mime, required String label, required String extension}) async {
  if (Platform.isAndroid || Platform.isIOS) {
    return await const MethodChannel('lumtub/windows_shell').invokeMethod<bool>('saveFile', {'name': name, 'mime': mime, 'bytes': bytes}) ?? false;
  }
  final location = await getSaveLocation(suggestedName: name, acceptedTypeGroups: [XTypeGroup(label: label, extensions: [extension])]);
  if (location == null) return false;
  // A temporary file first, so a failed write never leaves half a file.
  final temp = File('${location.path}.tmp');
  await temp.writeAsBytes(bytes, flush: true);
  await temp.rename(location.path);
  return true;
}
