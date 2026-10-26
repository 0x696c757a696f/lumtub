import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:lumtub/friendly_error.dart';

void main() {
  test('network failures read as something to act on', () {
    expect(friendlyError(TimeoutException('x')), contains('超时'));
    expect(friendlyError(const SocketException('Failed host lookup: www.youtube.com')), contains('连不上'));
    expect(friendlyError(http.ClientException('could not connect (error sending request)')), contains('连不上'));
    expect(friendlyError(Exception('HTTP 429 Too Many Requests')), contains('太频繁'));
    expect(friendlyError(Exception('HTTP 403')), contains('403'));
    expect(friendlyError(const HandshakeException('CERTIFICATE_VERIFY_FAILED')), contains('安全连接'));
  });

  test('other errors keep their message without the type name', () {
    expect(friendlyError(const FormatException('bad page')), 'bad page');
    expect(friendlyError(StateError('no more')), 'Bad state: no more');
    expect(friendlyError(Exception('')), isNotEmpty);
  });
}
