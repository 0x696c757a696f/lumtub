# media_kit_video 2.0.1, patched for Lumtub

Copied from pub.dev (MIT, see LICENSE) with only the Windows plugin kept.
The changes, marked "Lumtub" in the code:

- `windows/angle_surface_manager.cc`, `video_output.cc`: libmpv draws
  straight into a ring of four shared textures that Flutter samples, instead
  of into one texture copied into a second one for every frame shown (and
  Flutter's raster thread waiting for that copy). A frame is handed out only
  after `glFinish`, and a texture is drawn into again only once Flutter has
  taken two newer ones, so Flutter never samples a texture being drawn,
  which showed as black frames on some GPUs.
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
  still waiting and frames drawn against frames Flutter took, and return them through `VideoOutputManager.Stats`, so the
  log shows where frames are lost.
- `lib/src/video_controller/native_video_controller/real.dart`: on Windows
  `gpu-hwdec-interop` is `d3d11-egl` unless zero-copy `dxva2` is in `hwdec`,
  so making the output does not also make a Direct3D 9 device for the
  DXVA2 interop.
