import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/ui/rating_buttons.dart';

void main() {
  test('a like pressed here counts on top of YouTube\'s count', () {
    expect(countLikes('12', to: 'like'), '13');
    expect(countLikes('1,204', to: 'like'), '1205');
    expect(countLikes('', to: 'like'), '1');
    expect(countLikes('13', from: 'like'), '12');
    expect(countLikes('13', from: 'like', to: 'like'), '13');
    expect(countLikes('13', from: 'like', to: 'dislike'), '12');
    expect(countLikes('0', from: 'like'), '0');
    expect(countLikes(''), '0');
  });

  test('a rounded count stays as YouTube wrote it', () {
    expect(countLikes('1.2万', to: 'like'), '1.2万');
    expect(countLikes('3.4K', to: 'like'), '3.4K');
  });
}
