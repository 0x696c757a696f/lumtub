import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/learning/latin_language.dart';
import 'package:lumtub/learning/word_voice.dart';

void main() {
  test('Portuguese lines are told from Spanish ones', () {
    final guess = LatinLanguageGuess();
    expect(guess.guess('Você não sabe o que está fazendo, então eu vou com ela', const ['en', 'es', 'fr', 'de', 'it', 'pt']), 'pt');
    final other = LatinLanguageGuess();
    expect(other.guess('Yo no sé qué está pasando, pero los niños están muy bien', const ['en', 'es', 'fr', 'de', 'it', 'pt']), 'es');
  });

  test('the voice follows the subtitles’ region', () {
    expect(WordVoice.variantOf('pt', ['pt-PT']), 'pt-PT');
    expect(WordVoice.variantOf('pt', ['pt-BR']), 'pt-BR');
    expect(WordVoice.variantOf('pt', ['pt', null]), 'pt-BR');
    expect(WordVoice.variantOf('es', ['es-ES']), 'es-ES');
    expect(WordVoice.variantOf('es', ['es-419']), 'es-MX');
    expect(WordVoice.variantOf('es', ['es']), 'es-MX');
    expect(WordVoice.variantOf('fr', ['fr-CA']), 'fr');
    for (final code in ['pt', 'pt-BR', 'pt-PT', 'es-ES', 'es-MX']) {
      expect(WordVoice.azureVoices[code], isNotNull);
      expect(WordVoice.googleLanguages[code], isNotNull);
    }
  });
}
