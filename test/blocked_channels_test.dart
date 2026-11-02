import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/app_preferences.dart';
import 'package:lumtub/models.dart';
import 'package:lumtub/native_core.dart';

VideoItem _from(String channel) => VideoItem.fromJson({'id': 'aaaaaaaaaaa', 'title': 'x', 'channel': channel});

void main() {
  test('hosts tied to the Falun Gong media are blocked by their channel name, in either script', () {
    const prefs = AppPreferences();
    for (final channel in ['天亮时分', '天亮時分', '章天亮', '陈破空', '陳破空', '陳破空 Chen Pokong', 'Chen Pokong', 'Tianliang Times']) {
      expect(prefs.blocksGroup(_from(channel)), isTrue, reason: channel);
    }
    expect(prefs.blocksGroup(_from('破空')), isFalse);
  }, skip: NativeCore.instance == null ? 'needs LUMTUB_CORE_DLL' : null);
}
