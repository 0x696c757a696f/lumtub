part of 'app_controller.dart';

/// Live chat, chat replays and the bullet chat over the picture.
extension ChatActions on AppController {
  /// The most messages a live chat keeps; older ones leave the list.
  static const _liveChatKept = 2000;

  /// The most new messages of one flush that fly across the picture in a
  /// busy live chat; Super Chats and the like always do.
  static const _danmakuPerFlush = 40;

  /// Follows the chat of [item], live or a replay, in the view picked: read
  /// as YouTube's website reads it, or through yt-dlp when that fails
  /// before the first messages (YouTube's default view then).
  void _startChat(VideoItem item, int serial) {
    if (serial != _playSerial) return;
    final live = item.isLive;
    final view = preferences.chatView;
    _update(() {
      loadingReplayChat = true;
      loadingMoreChat = false;
      replayChatError = null;
    });
    logInfo('Reading the chat of ${item.id} (${live ? 'live' : 'replay'}, ${view.name})');
    var received = false;
    void follow(Stream<LiveChatBatch> batches, {required bool fallback}) {
      _currentChat = batches.listen(
        (batch) {
          if (serial != _playSerial) return;
          if (!received) {
            received = true;
            _chatHistory = live;
            chatViewShown = fallback ? null : batch.view;
            if (!live) loadingMoreChat = !fallback;
          }
          _takeBatch(batch, live: live);
          _currentChatFlushTimer ??= Timer(Duration(milliseconds: live ? 300 : 1000), () {
            _currentChatFlushTimer = null;
            _flushCurrentChat(serial, live: live);
          });
        },
        onError: (Object error) {
          if (serial != _playSerial) return;
          if (!fallback && !received && error is! NoLiveChat) {
            logWarn(
                'The chat of ${item.id} could not be read directly ($error); reading it through yt-dlp');
            final repository = _repository;
            if (repository != null) {
              final old = _currentChat;
              final messages = live
                  ? repository.liveChat.current(item.id).map((m) => LiveChatBatch(messages: [m]))
                  : Stream.fromFuture(repository.liveChat.replay(item.id))
                      .map((list) => LiveChatBatch(messages: list));
              follow(messages, fallback: true);
              unawaited(old?.cancel());
              return;
            }
          }
          logWarn('The chat of ${item.id} stopped: $error');
          _flushCurrentChat(serial, live: live);
          _update(() {
            if (error is! NoLiveChat && (replayChat.isEmpty || live)) {
              replayChatError = friendlyError(error);
            }
            loadingReplayChat = false;
            loadingMoreChat = false;
          });
        },
        onDone: () {
          _flushCurrentChat(serial, live: live);
          if (serial == _playSerial) {
            if (!live) logInfo('Chat replay of ${item.id}: ${replayChat.length} messages');
            _update(() {
              loadingReplayChat = false;
              loadingMoreChat = false;
            });
          }
        },
      );
    }

    follow(_chatFeed.follow(item.id, view), fallback: false);
  }

  /// Takes in what one answer of the chat brought, until the next flush.
  void _takeBatch(LiveChatBatch batch, {required bool live}) {
    if (batch.restricted != chatRestricted) chatRestricted = batch.restricted;
    for (final message in batch.messages) {
      if (!_currentChatIds.add(message.id)) continue;
      if (message.kind == LiveChatKind.mode) chatMode = message;
      _currentChatPending.add(message);
    }
    _chatRemoved.addAll(batch.removed);
    _chatRemovedAuthors.addAll(batch.removedAuthors);
    // A replay's answers follow each other in time: only the last one's ids
    // can come again, so a long replay does not keep every id.
    if (!live && _currentChatIds.length > 20000) {
      _currentChatIds
        ..clear()
        ..addAll(batch.messages.map((m) => m.id));
    }
  }

  void _flushCurrentChat(int serial, {required bool live}) {
    _currentChatFlushTimer?.cancel();
    _currentChatFlushTimer = null;
    if (serial != _playSerial) return;
    final removed = _chatRemoved.isNotEmpty || _chatRemovedAuthors.isNotEmpty;
    if (_currentChatPending.isEmpty && !removed) {
      if (loadingReplayChat) _update(() => loadingReplayChat = false);
      return;
    }
    bool kept(LiveChatMessage m) =>
        !_chatRemoved.contains(m.id) &&
        (m.authorChannelId == null || !_chatRemovedAuthors.contains(m.authorChannelId));
    final fresh = removed ? _currentChatPending.where(kept).toList() : [..._currentChatPending];
    _currentChatPending.clear();
    // One pass over the list for everything taken down since the last
    // flush, not one per message.
    final before = removed ? replayChat.where(kept) : replayChat;
    _chatRemoved.clear();
    _chatRemovedAuthors.clear();
    final next = [...before, ...fresh];
    if (live) {
      final now = DateTime.now();
      final ticker = [
        for (final message in fresh.reversed)
          if (message.tickerSeconds case final seconds?)
            (message, now.add(Duration(seconds: seconds))),
        for (final entry in chatTicker)
          if (entry.$2.isAfter(now) && kept(entry.$1)) entry,
      ];
      if (ticker.length != chatTicker.length || ticker.isNotEmpty) {
        chatTicker = List.unmodifiable(ticker.take(50));
      }
    }
    replayChat = List.unmodifiable(
        live && next.length > _liveChatKept ? next.sublist(next.length - _liveChatKept) : next);
    // The ids seen are kept for the messages kept, not for every one of a
    // stream that runs for hours: rebuilt once they are twice as many.
    if (live && _currentChatIds.length > _liveChatKept * 2) {
      _currentChatIds
        ..clear()
        ..addAll(replayChat.map((message) => message.id));
    }
    if (live && _chatHistory) {
      // What was said before the chat was opened is not flown.
      _chatHistory = false;
      _danmaku?.skip(fresh);
      _syncDanmaku(fresh: const []);
    } else {
      _syncDanmaku(fresh: live ? _busiest(fresh) : fresh);
    }
    if (loadingReplayChat) {
      _update(() => loadingReplayChat = false);
    } else if (!_disposed) {
      chatMessages.value++;
    }
  }

  /// The messages of a busy flush that fly: every paid one and the newest
  /// [_danmakuPerFlush] others, in order.
  static List<LiveChatMessage> _busiest(List<LiveChatMessage> fresh) {
    if (fresh.length <= _danmakuPerFlush) return fresh;
    var others = 0;
    final keep = List.filled(fresh.length, false);
    for (var i = fresh.length - 1; i >= 0; i--) {
      final paid = fresh[i].kind != LiveChatKind.message;
      if (paid || others < _danmakuPerFlush) keep[i] = true;
      if (!paid) others++;
    }
    return [
      for (var i = 0; i < fresh.length; i++)
        if (keep[i]) fresh[i]
    ];
  }

  /// Shows Top chat or every message, for this chat and the ones after.
  Future<void> setChatView(ChatView view) async {
    if (preferences.chatView == view) return;
    await savePreferences(preferences.copyWith(chatView: view));
    final item = playing;
    if (item == null || !hasChat || item.isUpcoming) return;
    _stopCurrentChat();
    _update(() {
      replayChat = const [];
      chatTicker = const [];
      chatMode = null;
    });
    _syncDanmaku();
    _startChat(item, _playSerial);
  }

  /// Whether the video playing has a chat to fly across it.
  bool get hasChat => playing != null && (playing!.isLive || playing!.liveStatus == 'was_live');

  /// Whether 弹幕 can fly over the video playing: its chat, or else the
  /// comments that name a moment of it.
  bool get hasDanmaku => playing != null && !playing!.isUpcoming;

  /// Starts, feeds or stops the 弹幕 for the video playing, the chat it
  /// has and the 弹幕 settings.
  /// [fresh] are the chat messages just added to [replayChat], the only
  /// ones a running overlay has not seen.
  void _syncDanmaku({List<LiveChatMessage>? fresh}) {
    final player = this.player;
    final item = playing;
    final settings = preferences.danmaku;
    final live = item?.isLive ?? false;
    final chat = hasChat;
    final key = player == null ||
            item == null ||
            !settings.enabled ||
            !hasDanmaku ||
            (!chat && !settings.comments)
        ? null
        : '${identityHashCode(player)}|${item.id}|$live|${preferences.chatView.name}|${settings.hashCode}';
    if (key != _danmakuFor) {
      // A new overlay is given the whole chat.
      fresh = null;
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
      _danmaku?.add(fresh ?? replayChat);
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
        logInfo(
            'Bullet chat of ${item.id}: ${_commentDanmaku.length} lines from ${read.length} comments');
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
    _chatRemoved.clear();
    _chatRemovedAuthors.clear();
    _chatHistory = false;
    unawaited(_currentChat?.cancel());
    _currentChat = null;
  }

  /// Asks again for the chat of the video playing after it failed.
  void retryChat() {
    final item = playing;
    if (item == null) return;
    _stopCurrentChat();
    _update(() => replayChat = const []);
    _startChat(item, _playSerial);
  }
}
