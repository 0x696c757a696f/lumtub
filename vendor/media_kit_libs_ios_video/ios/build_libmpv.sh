#!/bin/bash
# Builds MPVKit's libmpv for iPhone and iPad (arm64) again, with the
# patches in patch/ on top of MPVKit's own: patch/0004 adds the
# avfoundation video output (AVSampleBufferDisplayLayer), which iOS picture
# in picture needs.
#
# MPVKit's own build script does the work, at the release mpvkit.lock names,
# with three changes: only the device slice is built (no simulator), and
# FFmpeg and every other library come from that release's prebuilt archives
# instead of being compiled, so only libmpv is.
#
#   build_libmpv.sh <lock file> <output folder>
#
# Leaves <output folder>/libmpv.a and <output folder>/include/mpv/*.h.

set -euo pipefail

# Absolute: the build runs in a folder of its own.
LOCK="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
OUT="$(mkdir -p "$2" && cd "$2" && pwd)"
HERE="$(cd "$(dirname "$0")" && pwd)"

# The MPVKit release: the tag in the Libmpv URL of the lock file.
release=$(awk '$1 == "Libmpv" { print $3 }' "$LOCK" | sed -n 's#.*/releases/download/\([^/]*\)/.*#\1#p')
[ -n "$release" ] || { echo "No Libmpv release in $LOCK" >&2; exit 1; }

for tool in meson ninja pkg-config wget; do
  command -v "$tool" >/dev/null || brew install "$tool"
done

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
git clone --quiet --depth 1 --branch "$release" https://github.com/mpvkit/MPVKit.git "$WORK/MPVKit"
cd "$WORK/MPVKit"
# A backport names the mpv release that has it ("Upstream since: v0.42.0");
# once MPVKit builds that release or a newer one the patch is left out, so
# moving to a newer MPVKit needs no change here.
mpv_version=$(awk '/case .libmpv:/ { getline; gsub(/[^0-9.]/, ""); print; exit }' Sources/BuildScripts/XCFrameworkBuild/main.swift)
[ -n "$mpv_version" ] || { echo "No mpv version in MPVKit's main.swift" >&2; exit 1; }
echo "MPVKit $release builds mpv $mpv_version"
for patch in "$HERE"/patch/*.patch; do
  since=$(sed -n 's/^Upstream since: v\{0,1\}\([0-9.]*\).*/\1/p' "$patch" | head -n 1)
  if [ -n "$since" ] && [ "$(printf '%s\n%s\n' "$since" "$mpv_version" | sort -V | head -n 1)" = "$since" ]; then
    echo "Left out $(basename "$patch"): mpv $mpv_version has it (since $since)"
    continue
  fi
  cp "$patch" Sources/BuildScripts/patch/libmpv/
done

python3 - "$release" <<'PY'
import re, sys
release = sys.argv[1]
path = 'Sources/BuildScripts/XCFrameworkBuild/main.swift'
s = open(path).read()

def swap(old, new):
    global s
    if s.count(old) != 1:
        sys.exit(f'MPVKit build script changed: {old!r} not found once')
    s = s.replace(old, new)

# FFmpeg from the release's prebuilt archive instead of from source.
swap('return "https://github.com/FFmpeg/FFmpeg"',
     f'return "https://github.com/mpvkit/MPVKit/releases/download/{release}/FFmpeg-all.zip"')
swap('try BuildFFMPEG().buildALL()', 'try BuildFFmpegFromRelease().buildALL()')
s += '''

private class BuildFFmpegFromRelease: ZipBaseBuild {
    init() {
        super.init(library: .FFmpeg)
    }
}
'''
open(path, 'w').write(s)

path = 'Sources/BuildScripts/XCFrameworkBuild/base.swift'
s = open(path).read()
# The device only: platform=ios would add the simulator.
swap('options.platforms += [PlatformType.ios, PlatformType.isimulator]',
     'options.platforms += [PlatformType.ios]')
# No Package.swift for MPVKit's own releases: it downloads checksums that
# the FFmpeg archive above has none of.
swap('    func generatePackageManagerFile() throws {\n',
     '    func generatePackageManagerFile() throws {\n        return\n')
open(path, 'w').write(s)
PY

swift run --build-path ./.build --package-path Sources/BuildScripts build platform=ios "version=$release"

thin=dist/libmpv/ios/thin/arm64
[ -f "$thin/lib/libmpv.a" ] || { echo "libmpv.a was not built" >&2; ls -R dist/libmpv | head -50 >&2; exit 1; }
# grep reads all of nm's output: with -q it would stop early, and pipefail
# would take nm's broken pipe for a missing symbol.
if ! nm "$thin/lib/libmpv.a" 2>/dev/null | grep '_video_out_avfoundation' >/dev/null; then
  echo "libmpv.a has no avfoundation video output" >&2
  exit 1
fi

rm -rf "$OUT"
mkdir -p "$OUT/include"
cp "$thin/lib/libmpv.a" "$OUT/libmpv.a"
cp -R "$thin/include/mpv" "$OUT/include/mpv"
echo "$release" > "$OUT/release.txt"
ls -la "$OUT"
