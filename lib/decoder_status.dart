/// The decoding mode libmpv actually used for one codec.
///
/// Stored as structured JSON so UI wording can change without altering how
/// automatic format selection reads the result.
enum DecoderKind { unverified, software, hardware }

class DecoderStatus {
  final DecoderKind kind;

  /// The libmpv `hwdec-current` value, only set for [DecoderKind.hardware].
  final String? hwdec;

  const DecoderStatus._(this.kind, [this.hwdec]);
  const DecoderStatus.unverified() : this._(DecoderKind.unverified);
  const DecoderStatus.software() : this._(DecoderKind.software);
  const DecoderStatus.hardware(String hwdec) : this._(DecoderKind.hardware, hwdec);

  static const codecs = ['h264', 'vp9', 'av1'];

  /// Reads libmpv's `hwdec-current` property after playback started.
  factory DecoderStatus.fromMpv(String hwdecCurrent) {
    final value = hwdecCurrent.trim();
    if (value.isEmpty || value == 'no' || value == 'none') return const DecoderStatus.software();
    return DecoderStatus.hardware(value);
  }

  /// Accepts the structured form and the free-text strings older builds saved.
  static DecoderStatus? fromJson(Object? raw) {
    if (raw is Map) {
      final kind = DecoderKind.values.where((k) => k.name == raw['kind']).firstOrNull;
      final hwdec = raw['hwdec']?.toString();
      return switch (kind) {
        DecoderKind.unverified => const DecoderStatus.unverified(),
        DecoderKind.software => const DecoderStatus.software(),
        DecoderKind.hardware when _validHwdec(hwdec) => DecoderStatus.hardware(hwdec!),
        _ => null,
      };
    }
    if (raw is String) {
      if (raw == '尚未验证') return const DecoderStatus.unverified();
      if (raw.contains('软件') || raw.contains('不支持')) return const DecoderStatus.software();
      return _validHwdec(raw) ? DecoderStatus.hardware(raw) : null;
    }
    return null;
  }

  static bool _validHwdec(String? value) => value != null && RegExp(r'^[a-z0-9_-]{1,40}$').hasMatch(value);

  /// Normalises libmpv's `video-codec` description to a tracked codec key.
  static String? codecKey(String videoCodec) {
    final codec = videoCodec.toLowerCase();
    if (codec.contains('av1')) return 'av1';
    if (codec.contains('vp9')) return 'vp9';
    if (codec.contains('h264') || codec.contains('avc')) return 'h264';
    return null;
  }

  bool get isHardware => kind == DecoderKind.hardware;
  bool get isVerified => kind != DecoderKind.unverified;

  String get label => switch (kind) {
        DecoderKind.unverified => '尚未验证',
        DecoderKind.software => '软件解码已验证',
        DecoderKind.hardware => hwdec!,
      };

  Map<String, String> toJson() => {
        'kind': kind.name,
        if (hwdec != null) 'hwdec': hwdec!,
      };

  @override
  bool operator ==(Object other) => other is DecoderStatus && other.kind == kind && other.hwdec == hwdec;

  @override
  int get hashCode => Object.hash(kind, hwdec);

  @override
  String toString() => 'DecoderStatus(${kind.name}${hwdec == null ? '' : ', $hwdec'})';
}
