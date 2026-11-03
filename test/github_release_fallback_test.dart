import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/tool_manager.dart';

void main() {
  test('reads the tag from the latest release redirect', () {
    const repo = 'yt-dlp/yt-dlp-nightly-builds';
    expect(ToolManager.releaseTagOfRedirect(repo, 'https://github.com/yt-dlp/yt-dlp-nightly-builds/releases/tag/2026.11.02.233955'), '2026.11.02.233955');
    expect(ToolManager.releaseTagOfRedirect(repo, 'https://github.com/yt-dlp/yt-dlp-nightly-builds/releases'), isNull);
    expect(ToolManager.releaseTagOfRedirect(repo, 'https://evil.example/yt-dlp/yt-dlp-nightly-builds/releases/tag/x'), isNull);
    expect(ToolManager.releaseTagOfRedirect(repo, 'https://github.com/other/repo/releases/tag/x'), isNull);
    expect(ToolManager.releaseTagOfRedirect(repo, null), isNull);
  });

  test('parses SHA-256 sums files', () {
    final a = 'a' * 64, b = 'B' * 64;
    expect(ToolManager.parseSha256Sums('$a  yt-dlp_linux.zip\n$b *yt-dlp_win.zip\r\nnot a line\n'), [
      (a, 'yt-dlp_linux.zip'),
      ('b' * 64, 'yt-dlp_win.zip'),
    ]);
  });
}
