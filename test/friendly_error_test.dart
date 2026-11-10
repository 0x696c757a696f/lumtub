import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:lumtub/friendly_error.dart';

void main() {
  test('network failures read as something to act on', () {
    expect(friendlyError(TimeoutException('x')), contains('timed out'));
    expect(friendlyError(const SocketException('Failed host lookup: www.youtube.com')), contains("Can't reach"));
    expect(friendlyError(http.ClientException('could not connect (error sending request)')), contains("Can't reach"));
    expect(friendlyError(Exception('HTTP 429 Too Many Requests')), contains('Too many requests'));
    expect(friendlyError(Exception('HTTP 403')), contains('403'));
    expect(friendlyError(const HandshakeException('CERTIFICATE_VERIFY_FAILED')), contains('secure connection'));
  });

  test('other errors keep their message without the type name', () {
    expect(friendlyError(const FormatException('bad page')), 'bad page');
    expect(friendlyError(StateError('no more')), 'Bad state: no more');
    expect(friendlyError(Exception('')), isNotEmpty);
  });

  test('keywords only count for network errors, not any text', () {
    expect(friendlyError(const FormatException('bad timeout value in settings')), 'bad timeout value in settings');
    expect(friendlyError(Exception('video 4290 certificate of origin')), isNot(contains('secure connection')));
    expect(friendlyError(Exception('item 4031 not found')), contains('item 4031 not found'));
    expect(friendlyError(Exception('connection timed out')), contains('timed out'));
    expect(friendlyError(Exception('HTTP error 429')), contains('Too many requests'));
  });

  test('file errors read as something about the disk', () {
    expect(friendlyFileError(const FileSystemException('write failed', '/x', OSError('No space left on device', 28))), contains('disk is full'));
    expect(friendlyFileError(const FileSystemException('open failed', '/x', OSError('Permission denied', 13))), contains('No permission'));
    expect(friendlyFileError(const FileSystemException('open failed', '/x', OSError('No such file or directory', 2))), contains("wasn't found"));
    expect(friendlyFileError(const FileSystemException('weird', '/x')), contains('file or folder'));
    expect(friendlyFileError(const FormatException('bad')), 'bad');
  });

  test('yt-dlp output becomes a short message', () {
    expect(friendlyDownloadError('ERROR: [youtube] abc: Sign in to confirm you\u2019re not a bot'), contains('not a bot'));
    expect(friendlyDownloadError('ERROR: [youtube] abc: Private video. Sign in if you\'ve been granted access'), 'This video is private');
    expect(friendlyDownloadError('ERROR: [youtube] abc: Video unavailable'), contains("isn't available"));
    expect(friendlyDownloadError('ERROR: unable to download video data: HTTP Error 429: Too Many Requests'), contains('Too many requests'));
    expect(friendlyDownloadError('ERROR: unable to download video data: HTTP Error 403: Forbidden'), contains('403'));
    expect(friendlyDownloadError('ERROR: [Errno 28] No space left on device'), contains('disk is full'));
    final unknown = friendlyDownloadError('ERROR: something odd in Python');
    expect(unknown, isNot(contains('Python')));
    expect(unknown, contains('logs'));
  });

  test('download failures with a more exact cause are not called unavailable', () {
    expect(friendlyDownloadError('ERROR: [youtube] x: Sign in to confirm your age. This video may be inappropriate for some users.'), contains('age-restricted'));
    expect(friendlyDownloadError('ERROR: [youtube] x: Video unavailable. The uploader has not made this video available in your country'), contains('region'));
    expect(friendlyDownloadError('ERROR: [youtube] x: Requested format is not available'), contains('format'));
    expect(friendlyDownloadError('ERROR: ffmpeg is not available'), contains('ffmpeg'));
    expect(friendlyDownloadError('ERROR: [youtube] x: Sign in to confirm you’re not a bot'), contains('bot'));
  });
}
