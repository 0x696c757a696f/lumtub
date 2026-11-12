# Lumtub changes

A copy of media_kit_libs_android_video 1.3.8 that downloads libmpv from
[Predidit/libmpv-android-video-build](https://github.com/Predidit/libmpv-android-video-build)
(mpv master with libplacebo, FFmpeg from git, NDK r30, 16 KB pages) instead
of media-kit's v1.1.7. The jars have the same layout (`lib/<abi>/libmpv.so`
and `libmediakitandroidhelper.so`).

The release and the MD5 of each jar are at the top of `downloadDependencies`
in `android/build.gradle`; the weekly upstream check moves them to a newer
release.
