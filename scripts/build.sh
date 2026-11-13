#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
configuration="${1:-debug}"
architecture="${2:-native}"
if [[ "$configuration" != "debug" && "$configuration" != "release" ]]; then
    echo "Usage: $0 [debug|release] [native|arm64]" >&2
    exit 1
fi
build_args=(-c "$configuration")
case "$architecture" in
    native) app_dir="$project_dir/build/ViveBrush.app" ;;
    arm64)
        build_args+=(--arch arm64)
        app_dir="$project_dir/build/arm64/ViveBrush.app"
        ;;
    *)
        echo "Usage: $0 [debug|release] [native|arm64]" >&2
        exit 1
        ;;
esac
# Check this bundle only, so an isolated arm64 package can be built while the
# development app is running. lsof also detects apps launched by a relative path.
if [[ -f "$app_dir/Contents/MacOS/ViveBrush" ]] && \
    /usr/sbin/lsof -t "$app_dir/Contents/MacOS/ViveBrush" > /dev/null 2>&1; then
    echo "ViveBrush is running. Quit it from the pencil menu before rebuilding the app bundle." >&2
    exit 1
fi

swift build "${build_args[@]}"
binary_dir="$(swift build "${build_args[@]}" --show-bin-path)"
mkdir -p "$app_dir/Contents/MacOS"
mkdir -p "$app_dir/Contents/Frameworks"
mkdir -p "$app_dir/Contents/Resources"
cp "$binary_dir/ViveBrush" "$app_dir/Contents/MacOS/ViveBrush"
cp Resources/Info.plist "$app_dir/Contents/Info.plist"
ditto "$project_dir/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework" \
    "$app_dir/Contents/Frameworks/Sparkle.framework"
cp "$project_dir/.build/checkouts/Sparkle/LICENSE" "$app_dir/Contents/Resources/Sparkle-LICENSE.txt"
# A local ad-hoc signature is sufficient; no Apple Developer account is needed.
codesign --force --sign - --identifier com.vivebrush.app "$app_dir"
echo "Built: $app_dir"
