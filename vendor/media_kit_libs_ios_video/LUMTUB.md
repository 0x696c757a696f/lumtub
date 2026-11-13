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
