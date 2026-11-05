import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/app/app_controller.dart';
import 'package:lumtub/translation_services.dart';
import 'package:lumtub/ui/pages/translation_settings_page.dart';

void main() {
  Future<AppController> open(WidgetTester tester, TranslationConfig config) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = AppController();
    controller.preferences = controller.preferences.copyWith(translation: config);
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => TextButton(onPressed: () => openTranslationSettings(context, controller), child: const Text('open')))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return controller;
  }

  testWidgets('an AI model shows its provider, endpoint, model, key and prompt', (tester) async {
    await open(tester, const TranslationConfig(service: TranslationService.ai, aiPreset: 'deepseek'));
    for (final text in ['Provider', 'DeepSeek', 'https://api.deepseek.com/v1', 'deepseek-chat', 'API key', 'Subtitles (line for line)', 'Test translation']) {
      expect(find.text(text), findsWidgets, reason: text);
    }
    expect(find.text('Custom prompt'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the AI interface shows whichever service translates', (tester) async {
    await open(tester, const TranslationConfig(service: TranslationService.deepl, aiPreset: 'deepseek'));
    for (final text in ['AI interface', 'https://api.deepseek.com/v1', 'deepseek-chat', 'Test AI interface', 'Test translation', 'Speech recognition service', 'Groq (Whisper, free tier)', 'whisper-large-v3-turbo']) {
      expect(find.text(text), findsWidgets, reason: text);
    }
    expect(find.text('AI translation'), findsNothing);
    expect(find.text('Prompt'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a key is asked for with the text hidden', (tester) async {
    await open(tester, const TranslationConfig(service: TranslationService.deepl));
    expect(find.text('Not set'), findsWidgets);
    await tester.tap(find.text('API key').first);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).obscureText, isTrue);
    await tester.tap(find.byTooltip('Show'));
    await tester.pump();
    expect(tester.widget<TextField>(find.byType(TextField)).obscureText, isFalse);
  });
}
