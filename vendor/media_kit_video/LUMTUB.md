# media_kit_video 2.0.1, patched for Lumtub

`android/` is unchanged from 2.0.1; `pubspec.yaml` registers it again for
the Android build.

Copied from pub.dev (MIT, see LICENSE) with the Windows, Linux and macOS
plugins kept (`linux/` is unchanged from 2.0.1).
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
  It is drawn only while `secondaryKey` names a chosen subtitle, and when
  that changes the old line goes at once: mpv reports the text of a track
  turned off as unavailable, which media_kit ignores.
  Each subtitle is kept to two lines where it can be (drawn down to 85 %
  of its size), its wrapped lines evened out, no wider than 90 % of the
  picture (`SubtitleLine`).
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
- `lib/src/video_controller/video_controller.dart`, `native_video_controller/real.dart`:
  `VideoController.release` frees the video output while the player lives
  on, so Lumtub can make a new one, on a new Direct3D device, after the
  graphics device was lost (a driver reset).
- `windows/media_kit_video_plugin.cc`, `video_output.cc`, `video_output.h`
  (`engine_closing_`): when the plugin is destroyed with the engine at exit,
  video outputs no longer unregister their textures; the engine's texture
  registrar was already gone and the call crashed in flutter_windows.dll.
- `lib/src/utils/query_decoders.dart`: uses the libmpv already opened
  instead of calling `NativeLibrary.ensureInitialized()` again, which
  searched the default library names and, in the Linux AppImage, opened the
  system's libmpv beside the packaged one.
- `macos/Classes/plugin/TextureHW.swift`, `gl/OpenGLHelpers.swift`,
  `VideoOutput.swift` (in `macos/Classes/plugin/common/` and
  `common/darwin/`): when no accelerated OpenGL pixel format, context or
  texture cache can be made (a Mac virtual machine), the video is drawn in
  software instead of the app stopping on a nil value or `exit(1)`.
- `linux/texture_gl.cc`: each frame mpv draws is copied into a second
  texture, and the EGLImage Flutter reads refers to that one, not to mpv's
  render target. On Mesa (Intel Xe2, Mesa 25) a texture an EGLImage is made
  from stops receiving mpv's drawing, and the video stayed black. Taken from
  media-kit/media-kit#1464 (Starfallan/media-kit 85f0a69).
