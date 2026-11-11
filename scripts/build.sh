#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
configuration="${1:-debug}"
if [[ "$configuration" != "debug" && "$configuration" != "release" ]]; then
    echo "Usage: $0 [debug|release]" >&2
    exit 1
fi
if pgrep -x ViveBrush > /dev/null; then
    echo "ViveBrush is running. Quit it from the pencil menu before rebuilding the app bundle." >&2
    exit 1
fi

swift build -c "$configuration"
binary_dir="$(swift build -c "$configuration" --show-bin-path)"
app_dir="$project_dir/build/ViveBrush.app"
mkdir -p "$app_dir/Contents/MacOS"
cp "$binary_dir/ViveBrush" "$app_dir/Contents/MacOS/ViveBrush"
cp Resources/Info.plist "$app_dir/Contents/Info.plist"
# A local ad-hoc signature is sufficient; no Apple Developer account is needed.
codesign --force --sign - --identifier com.vivebrush.app "$app_dir"
echo "Built: $app_dir"
