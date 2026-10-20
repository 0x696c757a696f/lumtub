# media_kit_video 2.0.1, patched for YTPlus

Copied from pub.dev (MIT, see LICENSE) with only the Windows plugin kept.
The changes, marked "YTPlus" in the code:

- `windows/angle_surface_manager.cc` (`Read`): wait for the copy into the
  shared texture to finish before Flutter samples it, which otherwise shows
  black frames on some GPUs.
- `windows/video_output.cc` (`Resize`): resizing the texture freed it while
  Flutter's raster thread could still read it, and the texture callback
  used `at()` on a map entry that was not stored yet; both crashed the app
  when a video opened or the player changed size.
