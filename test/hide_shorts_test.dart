import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/app_preferences.dart';
import 'package:lumtub/models.dart';
import 'package:lumtub/native_core.dart';

void main() {
  VideoItem video(String id, {int? duration, String title = 'A video', String? url}) =>
      VideoItem(id: id, title: title, channel: 'C', duration: duration, url: url ?? 'https://www.youtube.com/watch?v=$id');

  test('hiding Shorts hides what For You counts as a Short', () {
    const prefs = AppPreferences(hideShorts: true);
    expect(prefs.shows(video('aaaaaaaaaa1', duration: 45)), isFalse);
    expect(prefs.shows(video('aaaaaaaaaa2', url: 'https://www.youtube.com/shorts/aaaaaaaaaa2')), isFalse);
    expect(prefs.shows(video('aaaaaaaaaa3', duration: 600)), isTrue);
    if (NativeCore.instance != null) expect(prefs.shows(video('aaaaaaaaaa4', duration: 150, title: 'Cat #shorts')), isFalse);
    expect(const AppPreferences().shows(video('aaaaaaaaaa1', duration: 45)), isTrue);
  });
}
