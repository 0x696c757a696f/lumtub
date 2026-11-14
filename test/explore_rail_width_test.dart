import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/app_preferences.dart';

void main() {
  test('the explore zone column keeps its dragged width', () {
    expect(const AppPreferences().exploreRailWidth, 220);
    final saved = const AppPreferences().copyWith(exploreRailWidth: 300).toJson();
    expect(AppPreferences.fromJson(saved).exploreRailWidth, 300);
    expect(AppPreferences.fromJson({'exploreRailWidth': 9000}).exploreRailWidth, 360);
  });
}
