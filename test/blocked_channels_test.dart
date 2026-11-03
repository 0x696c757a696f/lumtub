import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/app_preferences.dart';
import 'package:lumtub/models.dart';
import 'package:lumtub/native_core.dart';

VideoItem _from(String channel) => VideoItem.fromJson({'id': 'aaaaaaaaaaa', 'title': 'x', 'channel': channel});

void main() {
  test('hosts tied to the Falun Gong media are blocked by their channel name, in either script', () {
    const prefs = AppPreferences();
    for (final channel in ['天亮时分', '天亮時分', '章天亮', '陈破空', '陳破空', '陳破空 Chen Pokong', 'Chen Pokong', 'Tianliang Times', '熱點互動', '石濤聚焦', '乾淨世界', 'Gan Jing World', '李天笑', 'Trevor Loudon']) {
      expect(prefs.blocksGroup(_from(channel)), isTrue, reason: channel);
    }
    for (final channel in ['破空', '王赫野', '老外看中国', '未解之谜']) {
      expect(prefs.blocksGroup(_from(channel)), isFalse, reason: channel);
    }
  }, skip: NativeCore.instance == null ? 'needs LUMTUB_CORE_DLL' : null);
}
