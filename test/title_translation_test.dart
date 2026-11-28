import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/title_translation.dart';
import 'package:lumtub/translation.dart';
import 'package:lumtub/ui/video_card.dart' show TitleText;
import 'package:material_ui/material_ui.dart';

class _Recorder implements Translator {
  final asked = <String>[];
  final waiting = <String, Completer<String>>{};
  bool hold = false;
  bool fail = false;

  @override
  Future<String> translate(String text, String target) {
    asked.add(text);
    if (fail) return Future.error(const TranslationException('no'));
    if (hold) return (waiting[text] = Completer<String>()).future;
    return Future.value(text == 'Bonjour' ? 'Hello' : '[$target] $text');
  }
}

void main() {
  late _Recorder translator;
  late TitleTranslations titles;

  void configure(
          {TitleTranslation mode = TitleTranslation.replace,
          Object setup = 'a',
          bool Function(String)? needs}) =>
      titles.configure(
          mode: mode,
          translator: translator,
          target: 'en',
          needs: needs ?? (t) => !t.startsWith('EN '),
          setup: setup);

  setUp(() {
    translator = _Recorder();
  });

  test('asks only for titles that stay on screen, once each', () {
    fakeAsync((async) {
      titles = TitleTranslations(now: () => async.getClock(DateTime(2026)).now());
      configure();
      var woken = 0;
      void wake() => woken++;
      titles.listen('Bonjour', wake);
      titles.listen('Bonjour', wake);
      titles.listen('Passing by', wake);
      async.elapse(const Duration(milliseconds: 100));
      titles.unlisten('Passing by', wake);
      async.elapse(const Duration(milliseconds: 300));
      expect(translator.asked, ['Bonjour']);
      expect(titles.lookup('Bonjour'), 'Hello');
      expect(woken, 2, reason: 'both widgets showing the title are woken, nothing else');
      titles.listen('Bonjour', wake);
      async.elapse(const Duration(seconds: 1));
      expect(translator.asked, ['Bonjour'], reason: 'known answers are not asked again');
    });
  });

  test('titles already in the target language are never sent', () {
    fakeAsync((async) {
      titles = TitleTranslations(now: () => async.getClock(DateTime(2026)).now());
      configure();
      titles.listen('EN already', () {});
      titles.listen('', () {});
      titles.listen('x' * 400, () {});
      async.elapse(const Duration(seconds: 1));
      expect(translator.asked, isEmpty);
      expect(titles.lookup('EN already'), isNull);
    });
  });

  test('off sends nothing and shows nothing', () {
    fakeAsync((async) {
      titles = TitleTranslations(now: () => async.getClock(DateTime(2026)).now());
      configure(mode: TitleTranslation.off);
      titles.listen('Bonjour', () {});
      async.elapse(const Duration(seconds: 1));
      expect(translator.asked, isEmpty);
      expect(titles.lookup('Bonjour'), isNull);
      configure();
      async.elapse(const Duration(seconds: 1));
      expect(translator.asked, ['Bonjour'], reason: 'turning it on asks for the titles on screen');
      configure(mode: TitleTranslation.off);
      expect(titles.lookup('Bonjour'), isNull);
    });
  });

  test('no more than maxInFlight are asked at once', () {
    fakeAsync((async) {
      titles = TitleTranslations(maxInFlight: 3, now: () => async.getClock(DateTime(2026)).now());
      translator.hold = true;
      configure();
      for (var i = 0; i < 10; i++) {
        titles.listen('Title $i', () {});
      }
      async.elapse(const Duration(seconds: 1));
      expect(translator.asked, hasLength(3));
      translator.waiting['Title 0']!.complete('T0');
      async.elapse(const Duration(milliseconds: 10));
      expect(translator.asked, hasLength(4));
      expect(titles.lookup('Title 0'), 'T0');
    });
  });

  test('a new setup drops old answers and asks again; failures wait', () {
    fakeAsync((async) {
      titles = TitleTranslations(now: () => async.getClock(DateTime(2026)).now());
      translator.hold = true;
      configure();
      titles.listen('Bonjour', () {});
      async.elapse(const Duration(seconds: 1));
      final old = translator.waiting['Bonjour']!;
      translator.hold = false;
      configure(setup: 'b');
      old.complete('stale');
      async.elapse(const Duration(seconds: 1));
      expect(titles.lookup('Bonjour'), 'Hello',
          reason: 'the answer asked under the old setup is dropped');

      translator.fail = true;
      titles.listen('Ciao', () {});
      async.elapse(const Duration(seconds: 1));
      titles.unlisten('Ciao', () {});
      final before = translator.asked.length;
      titles.listen('Ciao', () {});
      async.elapse(const Duration(seconds: 1));
      expect(translator.asked.length, before, reason: 'a failed title is left alone for a while');
    });
  });

  test('a refusal pauses every title, longer each time, then asks again', () {
    fakeAsync((async) {
      titles = TitleTranslations(now: () => async.getClock(DateTime(2026)).now());
      translator.fail = true;
      configure();
      for (var i = 0; i < 5; i++) {
        titles.listen('Title $i', () {});
      }
      async.elapse(const Duration(seconds: 1));
      expect(translator.asked, hasLength(5));
      async.elapse(const Duration(seconds: 10));
      expect(translator.asked, hasLength(5), reason: 'paused 15 s once, not once per title');
      async.elapse(const Duration(seconds: 6));
      expect(translator.asked, hasLength(10));
      async.elapse(const Duration(seconds: 20));
      expect(translator.asked, hasLength(10), reason: 'the second pause is 30 s');
      translator.fail = false;
      async.elapse(const Duration(seconds: 15));
      expect(translator.asked, hasLength(15));
      expect(titles.lookup('Title 0'), '[en] Title 0');
    });
  });

  test('memory holds at most maxKept answers', () {
    fakeAsync((async) {
      titles = TitleTranslations(maxKept: 5, now: () => async.getClock(DateTime(2026)).now());
      configure();
      for (var i = 0; i < 20; i++) {
        titles.listen('Title $i', () {});
      }
      async.elapse(const Duration(seconds: 1));
      expect(titles.lookup('Title 19'), '[en] Title 19');
      expect(titles.lookup('Title 0'), isNull);
    });
  });

  testWidgets(
      'a title on screen shows its translation, the original on hover, and goes back when off',
      (tester) async {
    final translator = _Recorder();
    void set(TitleTranslation mode) => titleTranslations.configure(
        mode: mode, translator: translator, target: 'en', needs: (_) => true, setup: 'widget');
    set(TitleTranslation.replace);
    addTearDown(() => set(TitleTranslation.off));
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: SizedBox(
                width: 300, child: TitleText('Bonjour', maxLines: 2, style: TextStyle())))));
    expect(find.text('Bonjour'), findsOneWidget);
    // The dwell is measured on the wall clock.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(find.text('Hello'), findsOneWidget);
    expect(find.byWidgetPredicate((w) => w is Tooltip && w.message == 'Bonjour'), findsOneWidget);
    set(TitleTranslation.translationFirst);
    await tester.pump();
    expect(find.text('Hello'), findsOneWidget);
    expect(find.text('Bonjour'), findsOneWidget);
    set(TitleTranslation.off);
    await tester.pump();
    expect(find.text('Hello'), findsNothing);
    expect(translator.asked, ['Bonjour']);
  });
}
