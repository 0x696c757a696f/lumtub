part of 'app_controller.dart';

/// Saving videos, covers and subtitles, and building the repository and download manager.
extension DownloadActions on AppController {
  VideoRepository _repositoryFor(ToolPaths paths, CacheManager cacheManager, PlayerSettings settings) =>
      VideoRepository(
        paths.ytDlp,
        cacheDirectory: '${cacheManager.rootFor(settings).path}${Platform.pathSeparator}yt-dlp',
        deno: paths.deno,
        toolDirectories: paths.executableDirectories,
        proxy: () => proxy.ytDlpValue(this.settings.proxyMode),
        client: _http,
      )..streams.members = () => webSignIn;

  DownloadManager _downloadsFor(ToolPaths paths, AppDirectories directories) => DownloadManager(
        file: File('${directories.data.path}${Platform.pathSeparator}downloads.json'),
        ytDlpPath: paths.ytDlp,
        onFinished: (task) {
          if (!_disposed) _finishedDownloads.add(task);
        },
        defaultDirectory: DownloadManager.defaultDirectoryFor(Platform.environment, '${directories.data.path}${Platform.pathSeparator}downloads'),
        environment: () => _repository!.processEnvironment,
        // lumtub_core joins the streams, so no ffmpeg is needed.
        join: NativeCore.canJoin
            ? (request) {
                final json = request.toJson();
                return Isolate.run(() => NativeCore.join(json));
              }
            : null,
        cover: _coverBytes,
        recorder: NativeCore.canRecord ? CoreRecorder(sources: _liveSources, proxy: () => proxy.url) : null,
        options: () => DownloadOptions(
          proxy: proxy.ytDlpValue(settings.proxyMode),
          deno: paths.deno,
          cacheDirectory: _repository?.cacheDirectory,
          subtitleLanguages: settings.subtitleLanguage.ytDlpLangs,
          autoSubtitles: settings.subtitleMode == SubtitleMode.always,
          cutSponsors: settings.sponsorBlock && settings.sponsorCut,
        ),
        sponsorSegments: (id) => _sponsorBlock.segments(id, settings.sponsorCategories),
      );

  /// Queues [item] for download, and says so.
  /// A file name for [item]'s [suffix] (such as `.jpg`) in the download folder.
  String _downloadPath(VideoItem item, String suffix) {
    final title = item.title.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_').replaceAll(RegExp(r'\s+'), ' ').trim();
    final short = title.length > 120 ? title.substring(0, 120).trim() : title;
    final folder = downloads?.directory ?? Directory.systemTemp.path;
    return '$folder${Platform.pathSeparator}${short.isEmpty ? item.id : short} [${item.id}]$suffix';
  }

  /// Saves [item]'s largest cover image next to the downloads and returns
  /// its path.
  Future<String> saveCover(VideoItem item) async {
    final bytes = await _coverBytes(item.id);
    if (bytes == null) throw StateError(tr('This video has no cover image'));
    final file = File(_downloadPath(item, '.jpg'));
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes);
    return file.path;
  }

  /// The largest JPEG cover of video [id], or null when it has none.
  Future<List<int>?> _coverBytes(String id) async {
    for (final name in const ['maxresdefault', 'sddefault', 'hqdefault']) {
      final http.Response response;
      try {
        response = await _http.get(Uri.https('i.ytimg.com', '/vi/$id/$name.jpg')).timeout(const Duration(seconds: 20));
      } catch (_) {
        throw StateError(tr("Couldn't download the cover; check the network or proxy"));
      }
      // YouTube answers a missing size with a small placeholder or 404.
      if (response.statusCode != 200 || response.bodyBytes.length < 2000) continue;
      return response.bodyBytes;
    }
    return null;
  }

  /// The subtitles [item] offers, with the one translated into 第一字幕语言
  /// when the video has none in it.
  Future<List<SubtitleOption>> subtitleOptionsFor(VideoItem item) async {
    final known = playing?.id == item.id ? details : null;
    final repository = _repository;
    final offered = known?.subtitles ?? (repository == null ? const <SubtitleOption>[] : (await repository.details(item.id)).subtitles);
    final target = settings.subtitleLanguage.translation;
    final translation = hasOwnSubtitle(offered, target) ? null : translationOf(offered, target, language: known?.language);
    return [if (translation != null) translation, ...offered.where((o) => o.kind != SubtitleKind.translated)];
  }

  /// Saves [option] of [item] next to the downloads, as SRT or as WebVTT,
  /// and returns its path.
  Future<String> saveSubtitle(VideoItem item, SubtitleOption option, {bool srt = true}) async {
    final vtt = await File(await _subtitleFiles.wholePathFor(option)).readAsString();
    final file = File(_downloadPath(item, '.${option.language}.${srt ? 'srt' : 'vtt'}'));
    await file.parent.create(recursive: true);
    await file.writeAsString(srt ? toSrt(parseSubtitleCues(vtt)) : vtt);
    return file.path;
  }

  void download(VideoItem item, DownloadQuality quality, {DownloadSelection? selection}) {
    final manager = downloads;
    if (manager == null || item.isUpcoming || (item.isLive && !manager.canRecord)) return _notice(tr('Live streams cannot be downloaded'));
    if (item.isLive) {
      return _notice(manager.add(item, DownloadQuality.best) == null ? tr('Already in the download list') : tr('Recording the live stream; stop it in Downloads'));
    }
    _notice(manager.add(item, quality, selection: selection) == null ? tr('Already in the download list') : tr('Added to downloads'));
  }

  /// The picture and sound of live [videoId] to record: the tallest in a
  /// codec the playback settings allow, within their cap.
  Future<LiveSplit?> _liveSources(String videoId, {bool fresh = false}) async {
    final repository = _repository;
    if (repository == null) throw StateError(tr('Components are not ready yet'));
    if (fresh) repository.streams.forget(videoId);
    final video = await repository.streams.resolve(videoId, _format, formatSort: _formatSort, live: true);
    return LiveSplit.pick(video.info, _playback, above: 0);
  }

  /// The streams [videoId] can be downloaded as, from the extraction the
  /// player shares (one yt-dlp run per video).
  Future<DownloadFormats> downloadFormats(String videoId) async {
    final repository = _repository;
    if (repository == null) throw StateError(tr('Components are not ready yet'));
    final info = (await repository.streams.resolve(videoId, _format, formatSort: _formatSort)).info;
    // Automatic picks follow the playback order, so a download is in a codec
    // this PC decodes well; the quality strategy takes the best picture.
    final preference = settings.strategy == PlaybackStrategy.quality ? const <VideoCodec>[] : FormatPolicy.codecOrder(settings);
    final formats = await DownloadFormats.parseInBackground(info, preference: preference);
    // lumtub_core joins the streams, and takes AAC, Opus and Dolby sound.
    if (downloads?.join != null && formats.audio.any((a) => a.joins)) {
      return DownloadFormats(formats.video, [for (final a in formats.audio) if (a.joins) a], preference: formats.preference);
    }
    return formats;
  }
}
