import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/app/app_controller.dart';

void main() {
  test('copied errors keep only the host of an address', () {
    expect(diagnosticText('ClientException: refused, uri=https://rr3---sn-abc.googlevideo.com/videoplayback?expire=1&sig=SECRET&n=x'), 'ClientException: refused, uri=rr3---sn-abc.googlevideo.com');
    expect(diagnosticText('timed out\n  after 10 s'), 'timed out after 10 s');
  });

  test('exit addresses are cut short', () {
    expect(maskedAddress('203.0.113.45'), '203.0.113.x');
    expect(maskedAddress('2001:db8:85a3:8d3:1319:8a2e:370:7348'), '2001:db8:85a3:8d3:…');
  });

  test('reads Cloudflare\'s trace answer', () {
    final trace = readTrace('fl=1\nh=www.cloudflare.com\nip=198.51.100.7\nts=1\nloc=JP\nwarp=off\n');
    expect(trace?.ip, '198.51.100.7');
    expect(trace?.country, 'JP');
    expect(readTrace('<html>blocked</html>'), isNull);
  });
}
