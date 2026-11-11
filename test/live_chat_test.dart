import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/live_chat.dart';
import 'package:lumtub/live_chat_repository.dart';

void main() {
  String line(Map<String, Object?> renderer, {int? offset}) => jsonEncode({
        if (offset == null)
          'actions': [
            {'addChatItemAction': {'item': renderer}}
          ]
        else
          'replayChatItemAction': {
            'videoOffsetTimeMsec': '$offset',
            'actions': [
              {'addChatItemAction': {'item': renderer}}
            ],
          },
      });

  Map<String, Object?> textRenderer(String id, String text) => {
        'id': id,
        'timestampUsec': '1700000000123456',
        'message': {
          'runs': [
            {'text': text},
            {
              'emoji': {
                'shortcuts': [':wave:']
              }
            },
          ],
        },
        'authorName': {'simpleText': 'Alice'},
        'authorExternalChannelId': 'UCabcdefghijklmnopqrstuv',
        'authorPhoto': {
          'thumbnails': [
            {'url': 'https://example.test/s32'},
            {'url': 'https://example.test/s64'},
          ],
        },
      };

  test('reads a replay message and its video offset', () {
    final messages = LiveChatMessage.parseLine(line({'liveChatTextMessageRenderer': textRenderer('message-1', 'Hello ')}, offset: 12345));
    expect(messages, hasLength(1));
    final message = messages.single;
    expect(message.kind, LiveChatKind.message);
    expect(message.offset, const Duration(milliseconds: 12345));
    expect(message.text, 'Hello :wave:');
    expect(message.author, 'Alice');
    expect(message.authorAvatar, 'https://example.test/s64');
  });

  test('reads paid messages, stickers and membership notices', () {
    final paid = {
      ...textRenderer('paid-1', 'Keep it up!'),
      'purchaseAmountText': {'simpleText': '\$4.99'},
      'bodyBackgroundColor': 4280150454,
    };
    final sticker = {
      ...textRenderer('sticker-1', ''),
      'purchaseAmountText': {'simpleText': '€2.00'},
      'sticker': {
        'thumbnails': [
          {'url': 'https://example.test/sticker-small'},
          {'url': 'https://example.test/sticker-large'},
        ],
      },
    };
    final member = {
      'id': 'member-1',
      'authorName': {'simpleText': 'Bob'},
      'headerSubtext': {'simpleText': 'Member for 3 months'},
    };
    final messages = LiveChatMessage.parseLines([
      line({'liveChatPaidMessageRenderer': paid}),
      line({'liveChatPaidStickerRenderer': sticker}),
      line({'liveChatMembershipItemRenderer': member}),
    ].join('\n'));
    expect(messages.map((m) => (m.kind, m.amount, m.text)), [
      (LiveChatKind.paidMessage, '\$4.99', 'Keep it up!:wave:'),
      (LiveChatKind.paidSticker, '€2.00', ':wave:'),
      (LiveChatKind.membership, null, 'Member for 3 months'),
    ]);
    expect(messages[1].stickerUrl, 'https://example.test/sticker-large');
    expect((messages[0].color, messages[0].tickerSeconds), (0xFF1DE9B6, 120));
    expect((messages[1].color, messages[1].tickerSeconds), (null, null));
  });

  test('ignores non-chat actions and unknown renderers', () {
    expect(LiveChatMessage.parseLines('{"actions": []}\n{"actions":[{"addChatItemAction":{"item":{"unknownRenderer":{"id":"x"}}}}]}'), isEmpty);
  });

  test('a replay file read a few lines at a time gives every message in order', () async {
    final dir = await Directory.systemTemp.createTemp('lumtub_chat');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/replay.json');
    final lines = [
      for (var i = 0; i < 50; i++)
        line({
          'liveChatTextMessageRenderer': {
            'id': 'm$i',
            'message': {'runs': [{'text': 'hello $i'}]},
            'authorName': {'simpleText': 'A'},
          }
        }, offset: i * 1000),
    ];
    file.writeAsStringSync('${lines.join('\n')}\n\n');
    final whole = LiveChatMessage.parseLines(lines.join('\n'));
    final chunked = await LiveChatRepository.readReplayFile(file, chunkChars: 300);
    expect(whole, hasLength(50));
    expect(chunked.map((m) => m.id), whole.map((m) => m.id));
  });
}
