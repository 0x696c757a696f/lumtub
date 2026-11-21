part of 'app_controller.dart';

/// The details of the playing video and the AI summary made from them.
extension VideoDetailsActions on AppController {
  /// Forgets [videoId]'s AI 总结, so the next one is made again.
  void forgetSummary(String videoId) {
    _summaries.remove(videoId);
    _staleSummaries.add(videoId);
    final db = _textsDb;
    if (db != null) unawaited(db.forgetSummaries(video: videoId).catchError((Object e) => logDebug(() => 'Could not forget a summary: $e')));
  }

  String? summaryOf(String id) => _summaries[id];

  /// Whether AI 总结 has an AI service to ask.
  bool get canSummarize => intelligence.can(Capability.complete);

  /// AI 总结 of the video playing, from its subtitles in its own language,
  /// by the AI service set up under 翻译服务. Only the transcript and the
  /// title are sent, and only when asked. Kept in lumtub.db, so a video is
  /// summarized once in each interface language.
  Future<String> summarize({void Function(int done, int total)? onProgress}) async {
    final item = playing;
    final details = this.details;
    if (item == null) throw TranslationException(tr('No video is playing'));
    if (_summaries[item.id] case final done?) return done;
    final intelligence = this.intelligence;
    if (!intelligence.can(Capability.complete)) throw TranslationException(tr('Set up the AI interface and key under Translation & AI first'));
    final db = _textsDb;
    final language = currentLanguage.tag;
    if (db != null && !_staleSummaries.contains(item.id)) {
      try {
        if (await db.summary(item.id, language) case final saved?) return _keepSummary(item.id, saved);
      } on LocalDbException catch (e) {
        logWarn('Could not read a summary from lumtub.db: $e');
      }
    }
    final summary = await jobs.run('summary:${item.id}', (job) => _summarize(item, details, intelligence, onProgress), priority: JobPriority.watching);
    if (db != null) {
      try {
        await db.putSummary(item.id, language, intelligence.makerOf(Capability.complete), summary, keep: 500);
        _staleSummaries.remove(item.id);
      } on LocalDbException catch (e) {
        logWarn('Could not keep a summary in lumtub.db: $e');
      }
    }
    return _keepSummary(item.id, summary);
  }

  String _keepSummary(String id, String summary) {
    if (_summaries.length >= 30) _summaries.remove(_summaries.keys.first);
    _aiChapters(id, summary);
    return _summaries[id] = summary;
  }

  /// Whether the playing video's chapters on the progress bar are AI
  /// 概览's, as it had none of its own.
  bool get chaptersByAi => aiChaptersOf != null && aiChaptersOf == playing?.id;

  /// AI 概览's chapters on the progress bar of [id] while it plays, when
  /// it has none of its own.
  void _aiChapters(String id, String summary) {
    final details = this.details;
    if (playing?.id != id || details == null || (details.chapters.isNotEmpty && !chaptersByAi)) return;
    final overview = VideoOverview.parse(summary);
    if (overview == null || overview.chapters.length < 2) return;
    _update(() {
      this.details = details.withChapters([for (final c in overview.chapters) Chapter(c.start, c.end, c.title)]);
      aiChaptersOf = id;
    });
    chaptersChanged.value++;
  }

  Future<String> _summarize(VideoItem item, VideoDetails? details, Intelligence intelligence, void Function(int done, int total)? onProgress) async {
    final subtitles = details?.subtitles ?? const <SubtitleOption>[];
    final option = originalSubtitle(subtitles, language: details?.language) ?? subtitles.firstOrNull;
    final title = details?.title.isNotEmpty == true ? details!.title : item.title;
    Future<String> complete(String system, String user) => intelligence.complete(system, user);
    if (option == null) {
      // No subtitles, not even YouTube's automatic ones: the description
      // and chapters are all there is to go on.
      final description = details?.description ?? '';
      final chapters = [for (final c in details?.chapters ?? const <Chapter>[]) if (!chaptersByAi) (start: c.start, title: c.title)];
      if (!canSummarizeDescription(description, chapters)) throw TranslationException(tr('This video has no subtitles and its description is too short to summarize'));
      final summary = await summarizeDescription(complete, title, description, chapters);
      logInfo('Summarized ${item.id} from its description');
      return summary;
    }
    final source = await File(await _subtitleFile(option)).readAsString();
    final transcript = await summaryTranscript(source);
    final summary = await summarizeTranscript(complete, title, transcript, description: details?.description ?? '', onProgress: onProgress);
    logInfo('Summarized ${item.id} from ${transcript.chunks.length} part(s)');
    return summary;
  }

  /// lumtub.db, where notes are kept; older cores have none.
  LocalDb get _notesDb => _textsDb ?? (throw TranslationException(tr('Notes need a newer Lumtub core')));

  /// The notes on [video], in the order of the video.
  Future<List<VideoNote>> notesOf(String video) async => _textsDb == null ? const [] : _notesDb.notes(video: video);

  /// Keeps a note on the playing video at [at]: the subtitle words
  /// [quote] and what the person wrote about them.
  Future<void> addNote({required Duration at, String quote = '', String body = ''}) async {
    final item = playing;
    if (item == null) throw TranslationException(tr('No video is playing'));
    final title = details?.title.isNotEmpty == true ? details!.title : item.title;
    await _notesDb.putNote(video: item.id, title: title, at: at, quote: quote.trim(), body: body.trim());
    notesChanged.value++;
  }

  Future<void> changeNote(VideoNote note, {required String quote, required String body}) async {
    await _notesDb.putNote(id: note.id, video: note.video, quote: quote.trim(), body: body.trim());
    notesChanged.value++;
  }

  Future<void> forgetNote(VideoNote note) async {
    await _notesDb.forgetNote(note.id);
    notesChanged.value++;
  }

  /// AI 讲解 of [text], a line of the playing video's subtitles, read with
  /// the lines [before] and [after] it, in the interface language.
  Future<String> explainLine(String text, {List<String> before = const [], List<String> after = const []}) async {
    final intelligence = this.intelligence;
    if (!intelligence.can(Capability.complete)) throw TranslationException(tr('Set up the AI interface and key under Translation & AI first'));
    final item = playing;
    final title = details?.title.isNotEmpty == true ? details!.title : item?.title ?? '';
    return explainSubtitle(intelligence.complete, text, title: title, before: before, after: after);
  }

  /// [quote] and the person's [draft] made into a clear note by AI.
  Future<String> tidyNote(String quote, String draft) async {
    final intelligence = this.intelligence;
    if (!intelligence.can(Capability.complete)) throw TranslationException(tr('Set up the AI interface and key under Translation & AI first'));
    return tidyNoteText(intelligence.complete, quote, draft);
  }

  /// Starts resolving [item] before it is opened, such as when the pointer
  /// rests on its card ([hover]). Not on hover while a video plays: the
  /// yt-dlp run would take CPU from the playback for a guess.
  void prefetch(VideoItem item, {bool hover = false}) {
    // Each one starts yt-dlp; on battery only the next video in line is.
    if (hover && Power.saving) return;
    if (hover && player?.state.playing == true) return;
    if (ready && playing?.id != item.id && DateTime.now().isAfter(_rateLimitedUntil)) _repository?.streams.prefetch(item.id, _format, formatSort: _formatSort);
  }

  Future<void> _loadDetails(VideoItem item, int serial) async {
    int? length;
    try {
      VideoDetails loaded;
      final local = await downloads?.localVideo(item.id);
      final saved = local != null && local.info['title'] != null;
      if (saved) {
        // Saved with the download, so the page works offline.
        loaded = VideoDetails.fromJson(local.info);
      } else {
        try {
          // The extraction playback uses carries the details too.
          final resolved = await _repository!.streams.resolve(item.id, _formatFor(item.id), formatSort: _formatSort, membersOnly: item.membersOnly);
          loaded = resolved.details;
          if (resolved.info['duration'] case final num seconds when seconds > 0) length = seconds.round();
          if (serial == _playSerial) {
            _update(() {
              availableHeights = resolved.heightsFor(settings);
              availableFrameRates = resolved.frameRatesFor(settings);
              availableAudioLanguages = resolved.audioLanguages;
            });
            _tellSoftwareQuality();
            final lost = resolved.lostToDisabled(settings, _playback.maxHeight);
            if (lost != null) {
              _notice(tr("This video's {0}p is only in {1}, which is disabled; playing {2}p", [lost.height, lost.codecs.map((c) => c.label).join(' / '), lost.playing]));
            }
          }
        } catch (e) {
          // A second yt-dlp would meet the same 429, or the same network
          // the first one already tried twice.
          if (DateTime.now().isBefore(_rateLimitedUntil) || RegExp(r'\b429\b|Too Many Requests').hasMatch('$e') || StreamResolver.isTransient(e)) rethrow;
          loaded = await _repository!.details(item.id);
        }
      }
      // A video with no subtitles keeps the ones 语音识别 made for it.
      final speech = await _speechOptionFor(item.id, loaded);
      if (speech != null) loaded = loaded.withSpeechSubtitle(speech);
      if (serial == _playSerial) _fillPlaying(item, loaded, length);
      if (serial == _playSerial) {
        _update(() {
          details = loaded;
          aiChaptersOf = null;
          if (preferences.showRelated) related = _relatedTo(item, loaded.title.isNotEmpty ? loaded.title : item.title);
        });
        if (_summaries[item.id] case final summary?) _aiChapters(item.id, summary);
        // Once yt-dlp names the start time, wait for it rather than poll.
        if (waitingForStart && item.scheduledStart == null && loaded.scheduledStart != null) _waitForStart(item);
        unawaited(_localizeDetails(item.id, serial));
        if (speech != null && loaded.subtitles.length == 1) {
          _subtitlesSettled(serial);
          unawaited(_showSpeech(speech, serial));
        } else if (saved) {
          unawaited(_downloadedSubtitles(item, local, loaded, serial).whenComplete(() => _subtitlesSettled(serial)));
        } else {
          unawaited(_autoSubtitles(item, loaded, serial).whenComplete(() => _subtitlesSettled(serial)));
        }
      } else {
        _subtitlesSettled(serial);
      }
    } catch (_) {
      // The page still shows what the list already knew about the video.
      _subtitlesSettled(serial);
    } finally {
      if (serial == _playSerial) _update(() => loadingDetails = false);
    }
  }

  /// Subtitles for a downloaded video. Online, YouTube's, translations
  /// too, picked as when it streams; the download keeps only the ones
  /// saved with it, which are what plays offline.
  Future<void> _downloadedSubtitles(VideoItem item, LocalVideo local, VideoDetails saved, int serial) async {
    VideoDetails? online;
    try {
      final resolved = await _repository!.streams.resolve(item.id, _formatFor(item.id), formatSort: _formatSort, membersOnly: item.membersOnly).timeout(const Duration(seconds: 40));
      online = resolved.details;
    } catch (e) {
      logInfo('The download of ${item.id} keeps its own subtitles: $e');
    }
    if (serial != _playSerial) return;
    if (online == null || online.subtitles.isEmpty) {
      // Offline: the subtitles saved in one language each are picked as
      // first and second subtitle, each in its own style, as online. A
      // download with only a bilingual file shows that file.
      final own = local.subtitleOptions;
      if (own.isEmpty) {
        final player = this.player;
        if (player != null && await _fileLoaded(player, item.id, serial) && _openedLocal == item.id) await _addLocalSubtitles(local, serial);
        return;
      }
      final offline = saved.withSubtitles(own);
      _update(() => details = offline);
      await _autoSubtitles(item, offline, serial);
      return;
    }
    final merged = saved.withSubtitlesOf(online);
    _update(() => details = merged);
    await _autoSubtitles(item, merged, serial);
  }

  /// The playing video, and its place in the history, with what its
  /// details say and its card did not: a video opened from a link gets its
  /// title and channel, others their channel's id, views and upload day.
  void _fillPlaying(VideoItem item, VideoDetails loaded, int? length) {
    final current = playing?.id == item.id ? playing! : item;
    final filled = filledFromDetails(current, loaded, length: length);
    if (!saysMore(current, filled)) return;
    if (playing?.id == item.id) _update(() => playing = filled);
    if (history.any((other) => other.id == item.id)) unawaited(_history?.update(filledFromDetails(history.firstWhere((other) => other.id == item.id), loaded, length: length)));
  }

  /// Videos in the history opened from a link before their title was
  /// asked for: named by their id until now.
  Future<void> _nameLinkedVideos() async {
    final unnamed = [for (final item in history) if (isLinkPlaceholder(item)) item.id].take(50).toList();
    if (unnamed.isEmpty) return;
    var named = 0;
    for (final id in unnamed) {
      final found = await linkVideo(_http, id);
      if (_disposed) return;
      final at = history.indexWhere((item) => item.id == id);
      if (found == null || at < 0) continue;
      final old = history[at];
      await _history?.update(VideoItem(
        id: id,
        title: found.title,
        channel: found.channel,
        duration: old.duration,
        url: old.url,
        viewCount: old.viewCount,
        watching: old.watching,
        channelId: old.channelId,
        published: old.published,
        liveStatus: old.liveStatus,
        width: old.width,
        height: old.height,
      ));
      if (playing?.id == id && isLinkPlaceholder(playing!)) _update(() => playing = history[at]);
      named++;
    }
    if (named > 0) {
      logInfo('Named $named video(s) in the history opened from a link');
      _update(() {});
    }
  }

  /// yt-dlp asks YouTube in English, as it reads view counts and dates
  /// only in English; the title, description and chapter names are then
  /// fetched again in the interface language.
  Future<void> _localizeDetails(String videoId, int serial) async {
    final text = await relatedVideos.textFor(videoId);
    final current = details;
    if (text == null || current == null || serial != _playSerial) return;
    _update(() => details = current.localized(text.title, text.description, likes: text.likes));
  }

  VideoListLoader _relatedTo(VideoItem item, String title) {
    final repository = _repository!;
    // Long titles make poor queries; the first words carry the topic.
    final query = title.length > 60 ? title.substring(0, 60) : title;
    // YouTube's own suggestions come with the /next request the localized
    // title already makes; a search on the title stands in without them.
    final loader = VideoListLoader(
      () => repository.videosOr(() => relatedVideos.forVideo(item.id), query),
      pageSize: 13,
      limit: 12,
      where: (other) => other.id != item.id && !preferences.blocksGroup(other) && !preferences.isUnrecommended(other.channelId),
    )..addListener(_passOn('related'));
    loader.loadMore();
    return loader;
  }

  /// The channel of the playing video, once known.
  ChannelRef? get playingChannel {
    final item = playing;
    if (item == null) return null;
    final id = details?.channelId;
    if (id != null) return ChannelRef(id, details!.channel.isNotEmpty ? details!.channel : item.channel);
    return item.channelRef;
  }
}
