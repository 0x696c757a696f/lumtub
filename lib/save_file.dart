import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';

/// Asks where to save [bytes] as [name] and writes them there. False when
/// the person cancelled.
///
/// Android has no save dialog in file_selector, so the system's own
/// "create document" picker is used there.
Future<bool> saveFileAs(String name, Uint8List bytes, {required String mime, required String label, required String extension}) async {
  if (Platform.isAndroid) {
    return await const MethodChannel('lumtub/windows_shell').invokeMethod<bool>('saveFile', {'name': name, 'mime': mime, 'bytes': bytes}) ?? false;
  }
  final location = await getSaveLocation(suggestedName: name, acceptedTypeGroups: [XTypeGroup(label: label, extensions: [extension])]);
  if (location == null) return false;
  await File(location.path).writeAsBytes(bytes, flush: true);
  return true;
}
