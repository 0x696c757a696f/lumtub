import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Ed25519 signature checking (RFC 8032), for the learning pack's license
/// codes. It only verifies; nothing here signs. Plain integers keep it
/// short: one check takes some milliseconds, and it runs once at start.
bool ed25519Verify(
    {required List<int> publicKey, required List<int> message, required List<int> signature}) {
  if (publicKey.length != 32 || signature.length != 64) return false;
  final a = _decode(publicKey);
  final r = _decode(signature.sublist(0, 32));
  if (a == null || r == null) return false;
  final s = _littleEndian(signature.sublist(32));
  if (s >= _order) return false;
  final digest = sha512.convert([...signature.sublist(0, 32), ...publicKey, ...message]).bytes;
  final h = _littleEndian(digest) % _order;
  final left = _multiply(_base, s);
  final right = _add(r, _multiply(a, h));
  return _same(left, right);
}

final _p = (BigInt.one << 255) - BigInt.from(19);
final _order = (BigInt.one << 252) + BigInt.parse('27742317777372353535851937790883648493');
final _d = (-BigInt.from(121665) * _inverse(BigInt.from(121666))) % _p;
final _d2 = (_d * BigInt.two) % _p;
final _sqrtMinusOne = BigInt.two.modPow((_p - BigInt.one) ~/ BigInt.from(4), _p);

final _base = () {
  final y = (BigInt.from(4) * _inverse(BigInt.from(5))) % _p;
  final x = _recoverX(y, false)!;
  return _Point(x, y, BigInt.one, (x * y) % _p);
}();

class _Point {
  const _Point(this.x, this.y, this.z, this.t);
  final BigInt x, y, z, t;
}

BigInt _inverse(BigInt v) => v.modPow(_p - BigInt.two, _p);

BigInt _littleEndian(List<int> bytes) {
  var value = BigInt.zero;
  for (var i = bytes.length - 1; i >= 0; i--) {
    value = (value << 8) | BigInt.from(bytes[i]);
  }
  return value;
}

BigInt? _recoverX(BigInt y, bool odd) {
  if (y >= _p) return null;
  final y2 = (y * y) % _p;
  final x2 = ((y2 - BigInt.one) * _inverse((_d * y2 + BigInt.one) % _p)) % _p;
  if (x2 == BigInt.zero) return odd ? null : BigInt.zero;
  var x = x2.modPow((_p + BigInt.from(3)) ~/ BigInt.from(8), _p);
  if ((x * x - x2) % _p != BigInt.zero) x = (x * _sqrtMinusOne) % _p;
  if ((x * x - x2) % _p != BigInt.zero) return null;
  if (x.isOdd != odd) x = _p - x;
  return x;
}

_Point? _decode(List<int> bytes) {
  final copy = Uint8List.fromList(bytes);
  final odd = copy[31] & 0x80 != 0;
  copy[31] &= 0x7f;
  final y = _littleEndian(copy);
  final x = _recoverX(y, odd);
  if (x == null) return null;
  return _Point(x, y, BigInt.one, (x * y) % _p);
}

_Point _add(_Point a, _Point b) {
  final aa = ((a.y - a.x) * (b.y - b.x)) % _p;
  final bb = ((a.y + a.x) * (b.y + b.x)) % _p;
  final c = (a.t * _d2 * b.t) % _p;
  final dd = (a.z * BigInt.two * b.z) % _p;
  final e = bb - aa, f = dd - c, g = dd + c, h = bb + aa;
  return _Point((e * f) % _p, (g * h) % _p, (f * g) % _p, (e * h) % _p);
}

_Point _multiply(_Point point, BigInt scalar) {
  var result = _Point(BigInt.zero, BigInt.one, BigInt.one, BigInt.zero);
  var addend = point;
  var k = scalar;
  while (k > BigInt.zero) {
    if (k.isOdd) result = _add(result, addend);
    addend = _add(addend, addend);
    k >>= 1;
  }
  return result;
}

bool _same(_Point a, _Point b) =>
    (a.x * b.z - b.x * a.z) % _p == BigInt.zero && (a.y * b.z - b.y * a.z) % _p == BigInt.zero;
