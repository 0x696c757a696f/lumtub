part of 'app_controller.dart';

/// Live chat, chat replays and the bullet chat over the picture.
extension ChatActions on AppController {
  void _startCurrentChat(VideoItem item, int serial) {
    final repository = _repository;
    if (repository == null || serial != _playSerial) return;
    _update(() {
      loadingReplayChat = true;
      replayChatError = null;
    });
    logInfo('Following the live chat of ${item.id}');
    _currentChat = repository.liveChat.current(item.id).listen(
      (message) {
        if (serial != _playSerial || !_currentChatIds.add(message.id)) return;
        _currentChatPending.add(message);
        _currentChatFlushTimer ??= Timer(const Duration(milliseconds: 300), () {
          _currentChatFlushTimer = null;
          _flushCurrentChat(serial);
        });
      },
      onError: (Object error) {
        logWarn('The live chat of ${item.id} stopped: $error');
        if (serial == _playSerial) {
          _update(() {
            replayChatError = friendlyError(error);
            loadingReplayChat = false;
          });
        }
      },
      onDone: () {
        _flushCurrentChat(serial);
        if (serial == _playSerial) {
          _update(() => loadingReplayChat = false);
        }
      },
    );
  }

  void _flushCurrentChat(int serial) {
    if (serial != _playSerial || _currentChatPending.isEmpty) return;
    final next = [...replayChat, ..._currentChatPending];
    final now = DateTime.now();
    final ticker = [
      for (final message in _currentChatPending.reversed)
        if (message.tickerSeconds case final seconds?) (message, now.add(Duration(seconds: seconds))),
      for (final entry in chatTicker)
        if (entry.$2.isAfter(now)) entry,
    ];
    if (ticker.length != chatTicker.length || ticker.isNotEmpty) chatTicker = List.unmodifiable(ticker.take(50));
    _currentChatPending.clear();
    replayChat = List.unmodifiable(next.length > 2000 ? next.sublist(next.length - 2000) : next);
    _syncDanmaku();
    if (loadingReplayChat) {
      _update(() => loadingReplayChat = false);
    } else if (!_disposed) {
      chatMessages.value++;
    }
  }

  /// Whether the video playing has a chat to fly across it.
  bool get hasChat => playing != null && (playing!.isLive || playing!.liveStatus == 'was_live');

  /// Whether 弹幕 can fly over the video playing: its chat, or else the
  /// comments that name a moment of it.
  bool get hasDanmaku => playing != null && !playing!.isUpcoming;

  /// Starts, feeds or stops the 弹幕 for the video playing, the chat it
  /// has and the 弹幕 settings.
  void _syncDanmaku() {
    final player = this.player;
    final item = playing;
    final settings = preferences.danmaku;
    final live = item?.isLive ?? false;
    final chat = hasChat;
    final key = player == null || item == null || !settings.enabled || !hasDanmaku || (!chat && !settings.comments) ? null : '${identityHashCode(player)}|${item.id}|$live|${settings.hashCode}';
    if (key != _danmakuFor) {
      _danmakuFor = key;
      _danmaku?.stop();
      _danmaku = null;
      if (key == null) return;
      _danmaku = DanmakuOverlay(player!)..start(settings, live: live);
      if (live) {
        // What was said before 弹幕 was turned on stays in the chat.
        _danmaku!.skip(replayChat);
        return;
      }
    }
    if (key == null || item == null) return;
    if (chat) {
      _danmaku?.add(replayChat);
    } else {
      _loadCommentDanmaku(item);
      if (_commentDanmakuFor == item.id) _danmaku?.add(_commentDanmaku);
    }
  }

  /// Pages of comments read for the moments they name.
  static const _commentPages = 4;

  /// Reads the first comments of [item], once, for the lines that name a
  /// moment of it, and flies them as they come.
  void _loadCommentDanmaku(VideoItem item) {
    if (_commentDanmakuFor == item.id) return;
    _commentDanmakuFor = item.id;
    _commentDanmaku = const [];
    unawaited(() async {
      final read = <YoutubeComment>[];
      try {
        var page = await comments.video(item.id);
        for (var i = 0;; i++) {
          read.addAll(page.comments);
          if (_commentDanmakuFor != item.id) return;
          final length = item.duration == null ? null : Duration(seconds: item.duration!);
          final timed = timedComments(read, length: length);
          if (timed.length != _commentDanmaku.length) {
            _commentDanmaku = timed;
            _syncDanmaku();
          }
          final next = page.continuation;
          if (next == null || i + 1 >= _commentPages) break;
          page = await comments.more(next);
        }
        logInfo('Bullet chat of ${item.id}: ${_commentDanmaku.length} lines from ${read.length} comments');
      } catch (e) {
        logWarn('Could not read the comments of ${item.id} for bullet chat: $e');
      }
    }());
  }

  /// Turns 弹幕 on or off, or changes how they look.
  Future<void> setDanmaku(DanmakuSettings settings) async {
    await savePreferences(preferences.copyWith(danmaku: settings));
    _syncDanmaku();
  }

  void _stopCurrentChat() {
    _currentChatFlushTimer?.cancel();
    _currentChatFlushTimer = null;
    _currentChatPending.clear();
    _currentChatIds.clear();
    unawaited(_currentChat?.cancel());
    _currentChat = null;
  }

  /// Asks again for the chat of the video playing after it failed.
  void retryChat() {
    final item = playing;
    if (item == null) return;
    if (item.isLive) {
      unawaited(_currentChat?.cancel());
      _startCurrentChat(item, _playSerial);
    } else {
      unawaited(_loadReplayChat(item, _playSerial));
    }
  }

  Future<void> _loadReplayChat(VideoItem item, int serial) async {
    final repository = _repository;
    if (repository == null || serial != _playSerial) return;
    _update(() {
      loadingReplayChat = true;
      replayChatError = null;
    });
    try {
      final messages = await repository.liveChat.replay(item.id);
      if (serial == _playSerial) {
        _update(() => replayChat = messages);
        _syncDanmaku();
      }
    } catch (error) {
      if (serial == _playSerial) _update(() => replayChatError = friendlyError(error));
    } finally {
      if (serial == _playSerial) _update(() => loadingReplayChat = false);
    }
  }
}
