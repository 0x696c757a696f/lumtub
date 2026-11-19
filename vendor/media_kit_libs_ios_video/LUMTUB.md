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
(LGPL 2.1 or later, as mpv), rebased onto mpv 0.41 and rewritten as plain C
(no Objective-C, so nothing depends on mpv building it without ARC): it
hands each picture (a CVPixelBuffer, as VideoToolbox decodes it) and a
picture of the subtitles and OSD (a CGImage) to the app through a struct of
function pointers whose address it takes as `--wid`
(`struct lumtub_vo_host`; media_kit_video's `VideoSink.swift` makes it and
shows them in an AVSampleBufferDisplayLayer, which iOS picture in picture
takes). `0005-secondary-sub-scale.patch` is mpv 0.42's own
`secondary-sub-scale` (mpv commit 8ab3f8b6) on 0.41, so the second
subtitle is sized as on the desktop builds. The build uses
MPVKit's own build script at the locked release, compiling libmpv only:
FFmpeg and the other libraries come from that release's prebuilt archives.
lumtub-media-builds builds this recipe (the lock file, the script and the
patches, read from Lumtub's main branch) once a day and releases it as
`libmpv-ios-<MPVKit release>-<hash of the recipe>`; CI downloads that
release when `.github/pins.env` pins it (the weekly upstream check pins a
new one by checksum) and otherwise builds the recipe itself, keeping the
result in its cache.
