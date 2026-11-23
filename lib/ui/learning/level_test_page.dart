part of 'learning_page.dart';

/// Opens the two-minute level test; asks which language first when
/// [language] is null.
Future<void> openLevelTest(BuildContext context, Learning learning, {String? language}) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (context) => _LevelTestPage(learning: learning, language: language)));

/// The languages to offer, those with a dictionary here first.
List<String> _levelTestOrder(Learning learning) {
  bool here(String language) => DictionaryPack.values.any((p) => p.language == language && learning.stateOf(p) != PackState.missing);
  return [...levelTestLanguages.where(here), ...levelTestLanguages.where((l) => !here(l))];
}

/// The level's name on its language's scale, without the ≈ the result
/// says in words.
String _levelTestName(String language, int level) {
  final name = language == 'en' ? englishLevelName(EnglishLevel.values[(level - 1).clamp(0, EnglishLevel.gre.index)]) : LevelScale.of(language)!.nameOf(level);
  return name.startsWith('≈ ') ? name.substring(2) : name;
}

/// The level as [Learning.setLevel] takes it: English by its exam list.
int _levelTestSetting(String language, int level) => language == 'en' ? (level - 1).clamp(0, EnglishLevel.gre.index) : level.clamp(1, LevelScale.of(language)!.top);

/// The learning home's card: a test for each language.
class _LevelTestCard extends StatelessWidget {
  const _LevelTestCard({required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final learning = controller.learning;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Space.l),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _CardTitle(
            icon: AppIcons.chartBar,
            title: tr('Find your level in 2 minutes'),
            subtitle: tr('Say which words you know. Some are made up, to catch guessing.'),
          ),
          const SizedBox(height: Space.m),
          Wrap(spacing: Space.s, runSpacing: Space.s, children: [
            for (final language in _levelTestOrder(learning))
              ActionChip(
                label: Text(learning.levelIn(language) == null ? _languageName(language) : '${_languageName(language)} · ${_levelTestName(language, language == 'en' ? learning.levelIn(language)! + 1 : learning.levelIn(language)!)}'),
                onPressed: () => unawaited(openLevelTest(context, learning, language: language)),
              ),
          ]),
        ]),
      ),
    );
  }
}

enum _TestStage { pick, loading, missing, intro, asking, done }

class _LevelTestPage extends StatefulWidget {
  const _LevelTestPage({required this.learning, this.language});
  final Learning learning;
  final String? language;

  @override
  State<_LevelTestPage> createState() => _LevelTestPageState();
}

class _LevelTestPageState extends State<_LevelTestPage> {
  Learning get learning => widget.learning;
  final _focus = FocusNode();
  final _random = Random();

  var _stage = _TestStage.pick;
  String? _language;
  LevelTestBank? _bank;
  var _items = <LevelTestItem>[];
  final _answers = <(LevelTestItem, bool)>[];
  LevelTestResult? _result;
  var _applied = false;

  bool get _traditional => const {'zh-Hant', 'zh-HK'}.contains(currentLanguage.tag);

  @override
  void initState() {
    super.initState();
    if (widget.language != null) unawaited(_load(widget.language!));
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  Future<void> _load(String language) async {
    setState(() {
      _language = language;
      _stage = _TestStage.loading;
    });
    final bank = await learning.levelTestBank(language);
    if (!mounted) return;
    setState(() {
      _bank = bank;
      _stage = bank == null ? _TestStage.missing : _TestStage.intro;
    });
  }

  void _start() {
    setState(() {
      _items = _bank!.draw(_random);
      _answers.clear();
      _result = null;
      _applied = false;
      _stage = _TestStage.asking;
    });
    _focus.requestFocus();
  }

  void _answer(bool yes) {
    if (_stage != _TestStage.asking || _answers.length >= _items.length) return;
    setState(() {
      _answers.add((_items[_answers.length], yes));
      if (_answers.length == _items.length) {
        _result = LevelTestResult.of(_language!, _answers);
        _stage = _TestStage.done;
      }
    });
  }

  void _back() {
    if (_stage == _TestStage.asking && _answers.isNotEmpty) setState(_answers.removeLast);
  }

  Future<void> _apply() async {
    final result = _result!;
    await learning.setLevel(result.language, _levelTestSetting(result.language, max(1, result.level)));
    if (mounted) setState(() => _applied = true);
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || _stage != _TestStage.asking) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowRight || key == LogicalKeyboardKey.keyY || key == LogicalKeyboardKey.keyJ) {
      _answer(true);
    } else if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.keyN || key == LogicalKeyboardKey.keyF) {
      _answer(false);
    } else if (key == LogicalKeyboardKey.backspace) {
      _back();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final language = _language;
    return Scaffold(
      appBar: SkinAppBar(AppBar(title: Text(language == null ? tr('Level test') : tr('{0} level test', [_languageName(language)])))),
      body: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _key,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Padding(
              padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 600 ? Space.m : Space.l),
              child: switch (_stage) {
                _TestStage.pick => _pick(context),
                _TestStage.loading => const Center(child: CircularProgressIndicator()),
                _TestStage.missing => Center(child: ReviewPlate(child: _note(context, tr('The test could not be downloaded. Check the connection and try again.'), retry: () => unawaited(_load(language!))))),
                _TestStage.intro => Center(child: ReviewPlate(child: _intro(context))),
                _TestStage.asking => _asking(context),
                _TestStage.done => SingleChildScrollView(child: ReviewPlate(child: _done(context))),
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _note(BuildContext context, String text, {VoidCallback? retry}) => Padding(
        padding: const EdgeInsets.all(Space.l),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(text, textAlign: TextAlign.center),
          if (retry != null) ...[const SizedBox(height: Space.m), FilledButton(onPressed: retry, child: Text(tr('Try again')))],
        ]),
      );

  Widget _pick(BuildContext context) => ListView(children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.m),
          child: Text(tr('Which language?'), style: context.text.titleMedium),
        ),
        for (final language in _levelTestOrder(learning))
          ListTile(
            title: Text(_languageName(language)),
            subtitle: learning.levelIn(language) == null ? null : Text(tr('Now: {0}', [_levelTestName(language, language == 'en' ? learning.levelIn(language)! + 1 : learning.levelIn(language)!)])),
            trailing: Icon(AppIcons.caretRight),
            onTap: () => unawaited(_load(language)),
          ),
      ]);

  Widget _intro(BuildContext context) {
    final bank = _bank!;
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.all(Space.l),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(tr('About 70 words, 2 to 3 minutes'), style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: Space.m),
        Text(tr('Choose Know it only for words whose meaning you know. About a third are made up: saying you know one lowers your result, so don\'t guess.')),
        const SizedBox(height: Space.s),
        Text(tr('Every test draws new words. The result is approximate, from words alone, not an exam grade.'), style: context.text.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
        if (bank.beta) ...[
          const SizedBox(height: Space.s),
          Text(tr('Beta: the made-up words in this language have not been checked by native speakers yet.'), style: context.text.bodySmall?.copyWith(color: colors.tertiary)),
        ],
        const SizedBox(height: Space.l),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(onPressed: _start, child: Text(tr('Start the test'))),
        ),
      ]),
    );
  }

  Widget _asking(BuildContext context) {
    final item = _items[_answers.length];
    final colors = context.colors;
    final touch = Platform.isAndroid || Platform.isIOS;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ReviewPlate(
        padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.s),
        child: Row(children: [
          Expanded(child: LinearProgressIndicator(value: _answers.length / _items.length)),
          const SizedBox(width: Space.m),
          Text('${_answers.length + 1} / ${_items.length}', style: context.text.bodySmall),
          IconButton(
            tooltip: tr('Back one word (Backspace)'),
            onPressed: _answers.isEmpty ? null : _back,
            icon: Icon(AppIcons.arrowCounterClockwise, size: 18),
          ),
        ]),
      ),
      const SizedBox(height: Space.m),
      Expanded(
        child: ReviewPlate(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(Space.l),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(item.shown(traditionalChinese: _traditional), style: TextStyle(fontSize: 44, fontWeight: FontWeight.w600, color: colors.onSurface)),
              ),
            ),
          ),
        ),
      ),
      const SizedBox(height: Space.m),
      ReviewPlate(
        padding: const EdgeInsets.all(Space.s),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: () => _answer(false), child: Padding(padding: const EdgeInsets.symmetric(vertical: Space.s), child: Text(tr('Don\'t know'))))),
            const SizedBox(width: Space.s),
            Expanded(child: FilledButton(onPressed: () => _answer(true), child: Padding(padding: const EdgeInsets.symmetric(vertical: Space.s), child: Text(tr('Know it'))))),
          ]),
          if (!touch) ...[
            const SizedBox(height: Space.xs),
            Text(tr('Keys: ← or F don\'t know, → or J know it'), textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant)),
          ],
        ]),
      ),
    ]);
  }

  Widget _done(BuildContext context) {
    final result = _result!;
    final language = result.language;
    final colors = context.colors;
    final first = _levelTestName(language, 1);
    final headline = result.level == 0 ? tr('Below {0}', [first]) : tr('About {0}', [_levelTestName(language, result.level)]);
    final setting = _levelTestSetting(language, max(1, result.level));
    final already = learning.levelIn(language) == setting;
    return Padding(
      padding: const EdgeInsets.all(Space.l),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(tr('Your result'), style: context.text.bodyMedium?.copyWith(color: colors.onSurfaceVariant)),
        Text(headline, style: context.text.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: Space.xs),
        Text(tr('Score {0}%: the words you know, minus the made-up words you said you know', [(result.score * 100).round()]), style: context.text.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
        if (result.unreliable) ...[
          const SizedBox(height: Space.m),
          Text(tr('You said you know {0}% of the made-up words, so this result is likely too high. Try again and choose Know it only when you know the meaning.', [(result.falseAlarms * 100).round()]), style: TextStyle(color: colors.error)),
        ],
        const SizedBox(height: Space.l),
        Text(tr('Words you know at each level'), style: context.text.titleSmall),
        const SizedBox(height: Space.s),
        for (final MapEntry(key: level, value: known) in result.known.entries)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.xs),
            child: Row(children: [
              SizedBox(width: 120, child: Text(_levelTestName(language, level), maxLines: 1, overflow: TextOverflow.ellipsis)),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: known,
                    minHeight: 8,
                    color: level <= result.level ? colors.primary : colors.outline,
                    backgroundColor: colors.surfaceContainerHighest,
                  ),
                ),
              ),
              SizedBox(width: 48, child: Text('${(known * 100).round()}%', textAlign: TextAlign.end, style: context.text.bodySmall)),
            ]),
          ),
        const SizedBox(height: Space.m),
        Text(
          tr('Words above your level stand out in subtitles, and words at or below it count as known. You can change it any time in Learning settings.'),
          style: context.text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
        ),
        const SizedBox(height: Space.l),
        Wrap(alignment: WrapAlignment.end, spacing: Space.s, runSpacing: Space.s, children: [
          TextButton(onPressed: _start, child: Text(tr('Test again'))),
          if (_applied || already)
            FilledButton.icon(onPressed: () => Navigator.pop(context), icon: Icon(AppIcons.check), label: Text(tr('Done')))
          else
            FilledButton(onPressed: () => unawaited(_apply()), child: Text(tr('Use {0} as my level', [_levelTestName(language, max(1, result.level))]))),
        ]),
      ]),
    );
  }
}
