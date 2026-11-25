import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/app/app_controller.dart';
import 'package:lumtub/app_preferences.dart';
import 'package:lumtub/models.dart';
import 'package:lumtub/playing_list.dart';

void main() {
  final items = [for (final id in ['a', 'b', 'c']) VideoItem(id: id, title: id, channel: '', url: '')];

  test('a reversed playlist plays last to first', () {
    final list = PlayingList(id: 'p', title: 'P', items: items);
    expect([for (final item in list.ordered) item.id], ['a', 'b', 'c']);
    expect([for (final item in list.withReversed(true).ordered) item.id], ['c', 'b', 'a']);
  });

  test('the order is kept per playlist and the playing list follows it', () async {
    final controller = AppController();
    controller.playingList = PlayingList(id: 'p', title: 'P', items: items);
    await controller.setReversed('p', true);
    expect(controller.isReversed('p'), isTrue);
    expect(controller.isReversed('q'), isFalse);
    expect([for (final item in controller.queue) item.id], ['c', 'b', 'a']);
    expect(AppPreferences.fromJson(controller.preferences.toJson()).reversedPlaylists, ['p']);
    await controller.setReversed('p', false);
    expect(controller.preferences.reversedPlaylists, isEmpty);
    expect([for (final item in controller.queue) item.id], ['a', 'b', 'c']);
  });

  test('up next follows the video playing and the queue, a repeated video by its first place', () {
    VideoItem video(String id) => VideoItem(id: id, title: id, channel: '', url: '');
    final controller = AppController()
      ..queue = List.unmodifiable([for (final id in ['a', 'b', 'c', 'b', 'd']) video(id)])
      ..playing = video('b');
    expect([for (final item in controller.upNext) item.id], ['c', 'b', 'd']);
    expect(identical(controller.upNext, controller.upNext), isTrue, reason: 'made once per queue and video');
    expect(controller.previousInQueue?.id, 'a');
    expect(controller.upNextHas('d'), isTrue);
    expect(controller.upNextHas('b'), isTrue);
    expect(controller.upNextHas('a'), isFalse);
    controller.playing = video('d');
    expect(controller.upNext, isEmpty);
    expect(controller.upNextHas('c'), isFalse);
    controller.playing = video('elsewhere');
    expect(controller.upNext.map((item) => item.id), ['a', 'b', 'c', 'b', 'd']);
    expect(controller.upNextHas('a'), isTrue);
    controller.queue = List.unmodifiable([video('x'), video('elsewhere'), video('y')]);
    expect([for (final item in controller.upNext) item.id], ['y']);
  });
}
