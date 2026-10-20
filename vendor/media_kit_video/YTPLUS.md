# media_kit_video 2.0.1, patched for YTPlus

Copied from pub.dev (MIT, see LICENSE) with only the Windows plugin kept.
The one change is in `windows/angle_surface_manager.cc` (`Read`, marked
"YTPlus"): wait for the copy into the shared texture to finish before
Flutter samples it, which otherwise shows black frames on some GPUs.
