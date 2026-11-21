# Upscaling shaders

mpv user shaders behind Settings › Picture › Picture enhancement
(`lib/upscale_shaders.dart`). Each runs only while the picture is drawn at
least 1.2 to 1.4 times its own size.

| Tier | File | Source | Licence |
|------|------|--------|---------|
| Light | `ravu-lite-ar-r3.glsl` | [bjin/mpv-prescalers](https://github.com/bjin/mpv-prescalers) `master/ravu-lite-ar-r3.hook` | LGPL-3.0-or-later |
| Strong | `FSRCNNX_x2_8-0-4-1.glsl` | [igv/FSRCNN-TensorFlow](https://github.com/igv/FSRCNN-TensorFlow) release 1.1 | LGPL-3.0-or-later |
| Anime | `anime4k-a.glsl` | [bloc97/Anime4K](https://github.com/bloc97/Anime4K) 4.0, mode A (fast): Clamp_Highlights, Restore_CNN_M, Upscale_CNN_x2_M, AutoDownscalePre_x2, AutoDownscalePre_x4, Upscale_CNN_x2_S, joined in that order | MIT |

`anime4k-a.glsl` adds `//!WHEN OUTPUT.w NATIVE.w / 1.200 > OUTPUT.h NATIVE.h / 1.200 > *`
to the Clamp_Highlights and Restore passes, which have none upstream, so
nothing runs while the picture is not scaled up.

All three are fragment shaders, checked with mpv's OpenGL renderer on
OpenGL ES 3.0 (ANGLE on Windows, Android) and desktop OpenGL 4.1 (macOS).
Compute-shader upscalers such as ArtCNN are left out: mpv's OpenGL ES
renderer has no compute shaders, and macOS stops at OpenGL 4.1.
