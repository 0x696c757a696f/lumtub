# Lumtub changes

A copy of media_kit_libs_macos_video 1.1.4. media-kit's own macOS libmpv is
still mpv 0.36 with FFmpeg 6.0 (no AV1 hardware decoding on M3 and later).
This copy instead builds `Mpv.framework` from [MPVKit](https://github.com/mpvkit/MPVKit)'s
static libraries (mpv 0.41, FFmpeg 9, libplacebo, LGPL variant):
`macos/build_mpv_framework.sh` downloads the macOS slices listed in
`macos/mpvkit.lock`, checks their SHA-256 and links them into one dynamic
framework that exports only `mpv_*`, for arm64 and x86_64, macOS 12 and
later. The weekly upstream check moves `mpvkit.lock` to MPVKit's newest
release.
