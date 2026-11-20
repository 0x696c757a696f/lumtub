import 'dart:convert';

import 'ed25519.dart';

/// A learning pack license: who it was made for and when, signed with
/// the author's key. It is checked here, offline; nothing is sent
/// anywhere. Lumtub is open source, so the check can be taken out of a
/// build; it is kept plain on purpose, for the people who pay.
class LearningLicense {
  const LearningLicense({required this.name, required this.issued, required this.code});

  /// The buyer's name as they gave it, shown in the settings.
  final String name;
  final String issued;

  /// The code as it was entered, kept to check again at the next start.
  final String code;

  static const _prefix = 'LT1.';
  static const _context = 'lumtub-license-v1\n';

  /// The author's public key.
  static const publicKey = [
    92, 203, 159, 16, 74, 151, 175, 115, 174, 26, 30, 150, 154, 75, 64, 178, //
    245, 5, 87, 31, 181, 23, 50, 133, 133, 226, 91, 128, 111, 232, 16, 148,
  ];

  /// The license in [text], or null when it is not one signed by
  /// [key]. Spaces and line breaks a message app adds are ignored.
  static LearningLicense? parse(String text, {List<int> key = publicKey}) {
    final code = text.replaceAll(RegExp(r'\s'), '');
    if (!code.startsWith(_prefix)) return null;
    final parts = code.substring(_prefix.length).split('.');
    if (parts.length != 2) return null;
    try {
      final payload = base64Url.decode(base64Url.normalize(parts[0]));
      final signature = base64Url.decode(base64Url.normalize(parts[1]));
      if (!ed25519Verify(publicKey: key, message: [...utf8.encode(_context), ...payload], signature: signature)) return null;
      final fields = jsonDecode(utf8.decode(payload));
      if (fields is! Map || fields['p'] != 'learn') return null;
      return LearningLicense(name: '${fields['n'] ?? ''}'.trim(), issued: '${fields['d'] ?? ''}', code: code);
    } on FormatException {
      return null;
    }
  }
}
