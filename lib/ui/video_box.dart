import 'dart:io';
import 'dart:math';

import 'package:flutter/widgets.dart';

import '../app/app_controller.dart';
import '../device.dart';
import 'pages/watch_page.dart' show androidSubtitleScale, smallSubtitleScale;

/// Tells [controller] how large [child], which shows the video, is on
/// screen, so libmpv draws the picture at that size.
class VideoBox extends StatefulWidget {
  const VideoBox({super.key, required this.controller, required this.child, this.smallSubtitles = false, this.subtitlesOff});
  final AppController controller;
  final Widget child;

  /// Subtitles here are sized for a small window, as the mini player and
  /// picture-in-picture draw them.
  final bool smallSubtitles;

  /// Whether subtitles are left out of a box this size: libmpv then draws
  /// none either while this box shows the video.
  final bool Function(Size box)? subtitlesOff;

  @override
  State<VideoBox> createState() => _VideoBoxState();
}

class _VideoBoxState extends State<VideoBox> {
  @override
  void dispose() {
    widget.controller.hideVideoIn(this);
    widget.controller.subtitlesOffIn(this, false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ratio = MediaQuery.devicePixelRatioOf(context);
    return LayoutBuilder(builder: (context, constraints) {
      final box = constraints.biggest;
      if (box.isFinite) {
        widget.controller.showVideoIn(this, box * ratio);
        // Subtitles libmpv draws are sized as the Flutter view sizes them here.
        final small = widget.smallSubtitles;
        // Phones (Android and iOS) by the player's height, as YouTube's app: by area
        // against 1080p an upright phone player gets 9 px text.
        final textScale = Platform.isAndroid || Platform.isIOS ? androidSubtitleScale(box, Device.captionScale, small) : small ? smallSubtitleScale(box) : sqrt(box.width * box.height / (1920 * 1080));
        widget.controller.subtitleViewChanged(box, textScale, small ? (box.shortestSide / 720).clamp(0.3, 1.0) : 1);
        widget.controller.subtitlesOffIn(this, widget.subtitlesOff?.call(box) ?? false);
      }
      return widget.child;
    });
  }
}
