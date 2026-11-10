import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/app_preferences.dart';
import 'package:lumtub/models.dart';

void main() {
  VideoItem video(String id, {bool members = false}) =>
      VideoItem(id: id, title: 'A video', channel: 'C', duration: 600, url: 'https://www.youtube.com/watch?v=$id', membersOnly: members);

  test('members-only videos are hidden only when asked', () {
    const prefs = AppPreferences(hideMembersOnly: true);
    expect(prefs.shows(video('aaaaaaaaaa1', members: true)), isFalse);
    expect(prefs.shows(video('aaaaaaaaaa2')), isTrue);
    expect(const AppPreferences().shows(video('aaaaaaaaaa1', members: true)), isTrue);
  });

  test('the setting survives saving and loading', () {
    final saved = const AppPreferences().copyWith(hideMembersOnly: true).toJson();
    expect(AppPreferences.fromJson(saved).hideMembersOnly, isTrue);
    expect(AppPreferences.fromJson(const AppPreferences().toJson()).hideMembersOnly, isFalse);
  });
}
