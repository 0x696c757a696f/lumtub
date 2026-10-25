import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/community_posts.dart';
import 'package:lumtub/live_chat.dart';
import 'package:lumtub/native_core.dart';

void main() {
  test('the native core reads on a background isolate as it does on the UI one', () async {
    if (NativeCore.instance == null) return markTestSkipped('the native core is not built');
    const line = '{"replayChatItemAction":{"actions":[{"addChatItemAction":{"item":{"liveChatTextMessageRenderer":{"id":"m1","message":{"runs":[{"text":"hi"}]},"authorName":{"simpleText":"A"},"timestampUsec":"1"}}}}],"videoOffsetTimeMsec":"5000"}}';
    final here = LiveChatMessage.parseLines(line);
    expect(here, isNotEmpty);
    final there = await Isolate.run(() => LiveChatMessage.parseLines(line));
    expect(there.map((m) => m.text), here.map((m) => m.text));
    expect(await Isolate.run(() => CommunityPosts.read('<html></html>')), isNull);
  });
}
