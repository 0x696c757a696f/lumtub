import 'package:flutter/widgets.dart';

import '../app/app_controller.dart';

/// Tells [controller] how large [child], which shows the video, is on
/// screen, so libmpv draws the picture at that size.
class VideoBox extends StatefulWidget {
  const VideoBox({super.key, required this.controller, required this.child});
  final AppController controller;
  final Widget child;

  @override
  State<VideoBox> createState() => _VideoBoxState();
}

class _VideoBoxState extends State<VideoBox> {
  @override
  void dispose() {
    widget.controller.hideVideoIn(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ratio = MediaQuery.devicePixelRatioOf(context);
    return LayoutBuilder(builder: (context, constraints) {
      final box = constraints.biggest;
      if (box.isFinite) widget.controller.showVideoIn(this, box * ratio);
      return widget.child;
    });
  }
}
