import 'package:flutter/foundation.dart';

/// 剧场模式: the watch page gives the video the whole width of the content
/// area and moves the side panels below it. Not OS fullscreen. Kept for the
/// session, like YouTube keeps it per browser.
final theaterMode = ValueNotifier(false);

/// In 剧场模式 a wide window shows comments, up next and any chat as a
/// column beside the video; folded, the video takes the whole width.
final theaterChatOpen = ValueNotifier(true);

/// The tab the panel beside the video shows: chat, next, comments or
/// subtitles. Kept for the session, so the next video opens on it too;
/// setting it switches the panel there.
final sidePanelTab = ValueNotifier<String?>(null);

/// Whether the watch page shows a panel beside the video that can hold the
/// subtitle list, so the player opens the list there rather than over the
/// video. Set by the watch page as it lays out.
bool subtitleListBeside = false;
