# media_kit_video 2.0.1, patched for Lumtub

Copied from pub.dev (MIT, see LICENSE) with only the Windows plugin kept.
The changes, marked "Lumtub" in the code:

- `windows/angle_surface_manager.cc` (`Read`): wait for the copy into the
  shared texture to finish before Flutter samples it, which otherwise shows
  black frames on some GPUs.
- `windows/video_output.cc` (`Resize`): resizing the texture freed it while
  Flutter's raster thread could still read it, and the texture callback
  used `at()` on a map entry that was not stored yet; both crashed the app
  when a video opened or the player changed size.
- `lib/src/subtitle/subtitle_view.dart`: the secondary subtitle (the second
  entry of `Player.state.subtitle`) is drawn above the main one, not below,
  in its own style when `SubtitleViewConfiguration.secondaryStyle` is set.
- `lib/src/video_controller/native_video_controller/real.dart`: a size set
  with `setSize` is kept when the next video's size arrives, instead of
  being replaced by the video's own size.
- `windows/frame_stats.h`, `video_output.cc`, `angle_surface_manager.cc`,
  `video_output_manager.cc`, `media_kit_video_plugin.cc`: time each frame's
  render, ANGLE draw and Flutter read, count frames announced while one was
  still waiting, and return them through `VideoOutputManager.Stats`, so the
  log shows where frames are lost.
