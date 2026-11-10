part of 'app_controller.dart';

/// The details of the playing video and the AI summary made from them.
extension VideoDetailsActions on AppController {
  /// Forgets [videoId]'s AI 总结, so the next one is made again.
  void forgetSummary(String videoId) => _summaries.remove(videoId);

  String? summaryOf(String id) => _summaries[id];

  /// Whether AI 总结 has an AI service to ask.
  bool get canSummarize => aiServiceFor(preferences.translation, translationKeys, _http) != null;

  /// AI 总结 of the video playing, from its subtitles in its own language,
  /// by the AI service set up under 翻译服务. Only the transcript and the
  /// title are sent, and only when asked.
  Future<String> summarize({void Function(int done, int total)? onProgress}) async {
    final item = playing;
    final details = this.details;
    if (item == null) throw TranslationException(tr('No video is playing'));
    if (_summaries[item.id] case final done?) return done;
    final ai = aiServiceFor(preferences.translation, translationKeys, _http);
    if (ai == null) throw TranslationException(tr('Set up the AI interface and key under Translation & AI first'));
    final subtitles = details?.subtitles ?? const <SubtitleOption>[];
    final option = originalSubtitle(subtitles, language: details?.language) ?? subtitles.firstOrNull;
    final title = details?.title.isNotEmpty == true ? details!.title : item.title;
    final String summary;
    if (option == null) {
      // No subtitles, not even YouTube's automatic ones: the description
      // and chapters are all there is to go on.
      final description = details?.description ?? '';
      final chapters = [for (final c in details?.chapters ?? const <Chapter>[]) (start: c.start, title: c.title)];
      if (!canSummarizeDescription(description, chapters)) throw TranslationException(tr('This video has no subtitles and its description is too short to summarize'));
      summary = await summarizeDescription(ai, title, description, chapters);
      logInfo('Summarized ${item.id} from its description');
    } else {
      final source = await File(await _subtitleFile(option)).readAsString();
      final transcript = await summaryTranscript(source);
      summary = await summarizeTranscript(ai, title, transcript, onProgress: onProgress);
      logInfo('Summarized ${item.id} from ${transcript.chunks.length} part(s)');
    }
    if (_summaries.length >= 30) _summaries.remove(_summaries.keys.first);
    return _summaries[item.id] = summary;
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
    try {
      VideoDetails loaded;
      final local = await downloads?.localVideo(item.id);
      if (local != null && local.info['title'] != null) {
        // Saved with the download, so the page works offline.
        loaded = VideoDetails.fromJson(local.info);
      } else {
        try {
          // The extraction playback uses carries the details too.
          final resolved = await _repository!.streams.resolve(item.id, _format, formatSort: _formatSort, membersOnly: item.membersOnly);
          loaded = resolved.details;
          if (serial == _playSerial) {
            _update(() {
              availableHeights = resolved.heightsFor(settings);
              availableFrameRates = resolved.frameRatesFor(settings);
            });
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
      if (serial == _playSerial) {
        _update(() {
          details = loaded;
          if (preferences.showRelated) related = _relatedTo(item, loaded.title.isNotEmpty ? loaded.title : item.title);
        });
        // Once yt-dlp names the start time, wait for it rather than poll.
        if (waitingForStart && item.scheduledStart == null && loaded.scheduledStart != null) _waitForStart(item);
        unawaited(_localizeDetails(item.id, serial));
        if (speech != null && loaded.subtitles.length == 1) {
          _subtitlesSettled(serial);
          unawaited(_showSpeech(speech, serial));
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
