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
