import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/community_posts.dart';
import 'package:lumtub/link_video.dart';
import 'package:lumtub/models.dart';

void main() {
  test('a pasted link is named by its title and channel', () {
    final item = linkVideoOf('tNa-SfPF6pY', {
      'title': ' Living in Every Color For 24 Hours! ',
      'author_name': 'Some Channel',
      'width': 200,
      'height': 113
    })!;
    expect(item.title, 'Living in Every Color For 24 Hours!');
    expect(item.channel, 'Some Channel');
    expect(item.url, 'https://www.youtube.com/watch?v=tNa-SfPF6pY');
    expect(isLinkPlaceholder(item), isFalse);
    expect(linkVideoOf('tNa-SfPF6pY', {'error': 'Not Found'}), isNull);
    expect(linkVideoOf('tNa-SfPF6pY', 'Unauthorized'), isNull);
  });

  test('the details fill in a placeholder and what a card left out', () {
    final placeholder = linkPlaceholder('tNa-SfPF6pY');
    expect(isLinkPlaceholder(placeholder), isTrue);
    final details = VideoDetails(
        title: 'Living in Every Color',
        channel: 'Some Channel',
        channelId: 'UC1234567890123456789012',
        viewCount: 1200,
        uploadDate: DateTime(2026, 11));
    final filled = filledFromDetails(placeholder, details, length: 754);
    expect(filled.title, 'Living in Every Color');
    expect(filled.channel, 'Some Channel');
    expect(filled.channelId, 'UC1234567890123456789012');
    expect(filled.viewCount, 1200);
    expect(filled.duration, 754);
    expect(filled.published, DateTime(2026, 11));
    expect(isLinkPlaceholder(filled), isFalse);
    expect(saysMore(placeholder, filled), isTrue);
    // A named card keeps its own title and channel.
    const named = VideoItem(
        id: 'tNa-SfPF6pY',
        title: '每种颜色',
        channel: '频道',
        url: 'https://www.youtube.com/watch?v=tNa-SfPF6pY',
        viewCount: 5);
    final kept = filledFromDetails(named, details);
    expect(kept.title, '每种颜色');
    expect(kept.channel, '频道');
    expect(kept.viewCount, 5);
    expect(saysMore(kept, filledFromDetails(kept, details)), isFalse);
  });

  test('channel and playlist links are told apart from searches', () {
    expect(YoutubeLink.parse('https://www.youtube.com/channel/UCuAXFkgsw1L7xaCfnd5JJOw/videos'),
        isA<ChannelLink>().having((l) => l.id, 'id', 'UCuAXFkgsw1L7xaCfnd5JJOw'));
    expect(YoutubeLink.parse('youtube.com/@LinusTechTips'),
        isA<HandleLink>().having((l) => l.handle, 'handle', '@LinusTechTips'));
    expect(YoutubeLink.parse('https://m.youtube.com/@名字/featured'),
        isA<HandleLink>().having((l) => l.handle, 'handle', '@名字'));
    expect(
        YoutubeLink.parse(
            'https://www.youtube.com/playlist?list=PLFgquLnL59alCl_2TQvOiD5Vgm1hCaGSI'),
        isA<PlaylistLink>().having((l) => l.id, 'id', 'PLFgquLnL59alCl_2TQvOiD5Vgm1hCaGSI'));
    expect(YoutubeLink.parse('https://www.youtube.com/watch?v=dQw4w9WgXcQ'), isNull);
    expect(YoutubeLink.parse('lofi hip hop'), isNull);
    expect(YoutubeLink.parse('https://example.com/@name'), isNull);
    expect(YoutubeLink.parse('http://www.youtube.com/@name'), isNull);
  });

  test('post links open the post', () {
    expect(YoutubeLink.parse('https://www.youtube.com/post/UgkxAbCdEfGhIjKlMnOpQrStUvWx'),
        isA<PostLink>().having((l) => l.id, 'id', 'UgkxAbCdEfGhIjKlMnOpQrStUvWx'));
    expect(
        YoutubeLink.parse(
            'youtube.com/channel/UCuAXFkgsw1L7xaCfnd5JJOw/community?lb=UgkxAbCdEfGhIjKlMnOpQrStUvWx'),
        isA<PostLink>());
    expect(YoutubeLink.parse('https://www.youtube.com/post/nothing'), isNull);
  });

  test('the author of a post page is its channel', () {
    const html =
        '{"authorText":{"runs":[{"text":"Some \\"Quoted\\" Channel"}]},"authorEndpoint":{"clickTrackingParams":"x","browseEndpoint":{"browseId":"UCuAXFkgsw1L7xaCfnd5JJOw"}}}';
    final author = CommunityPosts.authorOf(html)!;
    expect(author.id, 'UCuAXFkgsw1L7xaCfnd5JJOw');
    expect(author.name, 'Some "Quoted" Channel');
    expect(CommunityPosts.authorOf('<html></html>'), isNull);
  });
}
