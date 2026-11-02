import 'package:flutter/foundation.dart';

/// 剧场模式: the watch page gives the video the whole width of the content
/// area and moves the side panels below it. Not OS fullscreen. Kept for the
/// session, like YouTube keeps it per browser.
final theaterMode = ValueNotifier(false);

/// In 剧场模式 a video with a chat shows it as a column beside the video,
/// as Twitch does; closed, the video takes the whole width.
final theaterChatOpen = ValueNotifier(true);
