import 'dart:convert';

import 'package:crypto/crypto.dart';

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

  /// The code's id: how the license server keeps its devices and how a
  /// code is named in its list of revoked ones.
  String get id => sha256.convert(utf8.encode(code)).toString().substring(0, 32);

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

/// The learning pack's SHA256SUMS, signed by the workflow that publishes
/// the dictionaries with the same key as licenses (under its own context,
/// so a signature for one is never one for the other). A dictionary is
/// used only when its sum is in a list signed so: a file swapped on the
/// download server, or the list beside it, is refused.
class SignedSums {
  SignedSums._(this.text);

  final String text;

  static const _context = 'lumtub-learning-sums-v1\n';

  /// [sums] when [signature] (base64) signs it, else null.
  static SignedSums? verify(List<int> sums, String signature, {List<int> key = LearningLicense.publicKey}) {
    try {
      final bytes = base64.decode(signature.trim());
      if (!ed25519Verify(publicKey: key, message: [...utf8.encode(_context), ...sums], signature: bytes)) return null;
      return SignedSums._(utf8.decode(sums));
    } on FormatException {
      return null;
    }
  }

  /// The SHA-256 sum listed for [name], or null.
  String? of(String name) => RegExp('^([0-9a-f]{64}) [ *]?${RegExp.escape(name)}\\s*\$', multiLine: true).firstMatch(text)?.group(1);
}

/// The license server's word that a code is active on one device: the
/// code's id, the device and the day, signed with the license key under
/// its own context. Kept beside the code, it lets the pack work offline
/// on that device; copied to another, it does not match.
class ActivationReceipt {
  const ActivationReceipt._(this.day);

  /// The day the server last confirmed it.
  final DateTime day;

  static const _prefix = 'LA1.';
  static const _context = 'lumtub-activation-v1\n';

  /// The receipt in [text] when it is signed and for [codeId] on
  /// [device], else null.
  static ActivationReceipt? verify(String text, {required String codeId, required String device, List<int> key = LearningLicense.publicKey}) {
    if (!text.startsWith(_prefix)) return null;
    final parts = text.substring(_prefix.length).split('.');
    if (parts.length != 2) return null;
    try {
      final payload = base64Url.decode(base64Url.normalize(parts[0]));
      final signature = base64Url.decode(base64Url.normalize(parts[1]));
      if (!ed25519Verify(publicKey: key, message: [...utf8.encode(_context), ...payload], signature: signature)) return null;
      final fields = jsonDecode(utf8.decode(payload));
      if (fields is! Map || fields['c'] != codeId || fields['v'] != device) return null;
      final day = DateTime.tryParse('${fields['t']}');
      return day == null ? null : ActivationReceipt._(day);
    } on FormatException {
      return null;
    }
  }
}
