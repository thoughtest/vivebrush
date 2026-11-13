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
# Build a fresh bundle so repeat builds don't merge stale framework files or
# overwrite the read-only license copied by an earlier build.
mkdir -p "$(dirname "$app_dir")"
staging_dir="$(mktemp -d "$(dirname "$app_dir")/.vivebrush-build.XXXXXX")"
trap 'rm -rf "$staging_dir"' EXIT
staged_app="$staging_dir/ViveBrush.app"
mkdir -p "$staged_app/Contents/MacOS" "$staged_app/Contents/Frameworks" "$staged_app/Contents/Resources"
cp "$binary_dir/ViveBrush" "$staged_app/Contents/MacOS/ViveBrush"
cp Resources/Info.plist "$staged_app/Contents/Info.plist"
ditto "$project_dir/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework" \
    "$staged_app/Contents/Frameworks/Sparkle.framework"
cp "$project_dir/.build/checkouts/Sparkle/LICENSE" "$staged_app/Contents/Resources/Sparkle-LICENSE.txt"
# A local ad-hoc signature is sufficient; no Apple Developer account is needed.
codesign --force --sign - --identifier com.vivebrush.app "$staged_app"
codesign --verify --deep --strict "$staged_app"
if [[ -f "$app_dir/Contents/MacOS/ViveBrush" ]] && \
    /usr/sbin/lsof -t "$app_dir/Contents/MacOS/ViveBrush" > /dev/null 2>&1; then
    echo "ViveBrush started during the build. Quit it before replacing the app bundle." >&2
    exit 1
fi
rm -rf "$app_dir"
mv "$staged_app" "$app_dir"
echo "Built: $app_dir"
