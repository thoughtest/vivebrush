#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/vivebrush-checks.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT
swiftc -parse-as-library -target "$(uname -m)-apple-macosx14.0" \
    Sources/ViveBrush/ContentView.swift Tests/DrawingStateChecks.swift \
    -o "$test_dir/DrawingStateChecks"
"$test_dir/DrawingStateChecks"
swift package resolve
framework_dir="$project_dir/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64"
for configuration in debug release; do
    swift_args=(-Onone)
    if [[ "$configuration" == "debug" ]]; then swift_args+=(-D DEBUG); fi
    swiftc -parse-as-library "${swift_args[@]}" -target "$(uname -m)-apple-macosx14.0" \
        -F "$framework_dir" -framework Sparkle -Xlinker -rpath -Xlinker "$framework_dir" \
        Sources/ViveBrush/AppUpdater.swift Tests/AppUpdaterChecks.swift \
        -o "$test_dir/AppUpdaterChecks"
    "$test_dir/AppUpdaterChecks"
done
python3 Tests/AppcastChecks.py
