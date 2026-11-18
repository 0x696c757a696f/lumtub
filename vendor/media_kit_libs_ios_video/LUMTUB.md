# Lumtub changes

A copy of media_kit_libs_ios_video 1.1.4. media-kit's own iOS libmpv is
still mpv 0.36 with FFmpeg 6.0. This copy instead builds `Mpv.framework`
from [MPVKit](https://github.com/mpvkit/MPVKit)'s static libraries (mpv
0.41, FFmpeg 9, libplacebo, LGPL variant), the same release the macOS copy
uses: `ios/build_mpv_framework.sh` downloads the iOS device slices listed in
`ios/mpvkit.lock`, checks their SHA-256 and links them into one dynamic
framework that exports only `mpv_*`, for arm64, iOS 15 and later. The
weekly upstream check moves `mpvkit.lock` here and in
media_kit_libs_macos_video to MPVKit's newest release together.

The simulator is not built for.

libmpv itself is MPVKit's, built again with the patches in `ios/patch/`
(`ios/build_libmpv.sh`, run by the Makefile before the framework is
linked): `0004-avfoundation-video-output.patch` adds the `avfoundation`
video output from [Streamyfin's MPVKit fork](https://github.com/streamyfin/MPVKit)
(LGPL 2.1 or later, as mpv), rebased onto mpv 0.41, with one change: a layer
that iOS interrupted in the background is flushed before the next frame. It
draws into an AVSampleBufferDisplayLayer (`--wid`), which iOS picture in
picture takes; VideoToolbox's frames go to it as they are. The build uses
MPVKit's own build script at the locked release, compiling libmpv only:
FFmpeg and the other libraries come from that release's prebuilt archives.
CI keeps the result in its cache, keyed on the lock file, the script and the
patches.
