import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/learning/vocabulary.dart';
import 'package:lumtub/ui/build_error_box.dart';
import 'package:lumtub/ui/learning/learning_page.dart' show newestFirstWords;
import 'package:material_ui/material_ui.dart';

class _Broken extends StatelessWidget {
  const _Broken();
  @override
  Widget build(BuildContext context) => throw StateError('broken');
}

void main() {
  test('an empty vocabulary book is not sorted in place', () {
    final empty = List<VocabularyWord>.unmodifiable(const []);
    expect(newestFirstWords(empty), isEmpty);
    final words = List<VocabularyWord>.unmodifiable([
      VocabularyWord(word: 'a', language: 'it', added: DateTime(2026)),
      VocabularyWord(word: 'b', language: 'it', added: DateTime(2026, 2)),
    ]);
    expect(newestFirstWords(words).map((w) => w.word), ['b', 'a']);
    expect(identical(newestFirstWords(words), newestFirstWords(words)), isTrue);
  });

  testWidgets('a part that fails to build is a short note, not a page-tall box', (tester) async {
    final builder = ErrorWidget.builder;
    ErrorWidget.builder = (details) => const BuildErrorBox();
    addTearDown(() => ErrorWidget.builder = builder);
    final errors = <FlutterErrorDetails>[];
    final report = FlutterError.onError;
    FlutterError.onError = errors.add;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListView(children: const [
          SizedBox(height: 50),
          _Broken(),
          SizedBox(height: 50, child: Text('after'))
        ]),
      ),
    ));
    FlutterError.onError = report;
    expect(errors.single.exception, isA<StateError>());
    expect(tester.getSize(find.byType(BuildErrorBox)).height,
        lessThanOrEqualTo(BuildErrorBox.maxHeight));
    expect(find.text('after'), findsOneWidget);
    expect(find.textContaining('could not be shown'), findsOneWidget);
  });
}
