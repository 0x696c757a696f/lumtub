# Lumtub changes

A copy of media_kit_libs_windows_video 1.0.11. The changes, marked "Lumtub"
in `windows/CMakeLists.txt`:

- An ARM64 build takes libmpv and ANGLE already unpacked by the build
  workflow (media_kit publishes x64 archives only).
- The x64 libmpv and ANGLE archives are checked by SHA-256 instead of MD5
  (the same archives; their MD5 sums matched the old pins).
