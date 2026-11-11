#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
artifact_dir="$project_dir/dist/$version"
app_dir="$project_dir/build/arm64/ViveBrush.app"
asset_name="ViveBrush-$version-arm64"

"$project_dir/scripts/build.sh" release arm64
if [[ "$(lipo -archs "$app_dir/Contents/MacOS/ViveBrush")" != "arm64" ]]; then
    echo "The distribution app must contain only the arm64 architecture." >&2
    exit 1
fi
codesign --verify --deep --strict --verbose=2 "$app_dir"

staging_dir="$(mktemp -d "${TMPDIR:-/tmp}/vivebrush-package.XXXXXX")"
trap 'rm -rf "$staging_dir"' EXIT
mkdir -p "$artifact_dir" "$staging_dir/disk-image"
ditto "$app_dir" "$staging_dir/disk-image/ViveBrush.app"
ln -s /Applications "$staging_dir/disk-image/Applications"
cat > "$staging_dir/disk-image/INSTALL.txt" <<'INSTALL'
ViveBrush — Apple Silicon (arm64), macOS 14 이상

1. ViveBrush.app을 Applications 폴더로 드래그합니다.
2. 응용 프로그램에서 ViveBrush를 실행합니다.
3. 메뉴 막대의 연필 아이콘 또는 Option + Tab으로 판서를 시작합니다.
4. Esc / Q로 판서를 종료합니다. 화면 녹화 권한은 필요하지 않습니다.

이 테스트 빌드는 ad-hoc 서명이며 Developer ID 서명 및 Apple 공증은 없습니다.
첫 실행 시 macOS에서 개발자를 확인할 수 없다는 경고가 표시될 수 있습니다.
출처와 파일을 신뢰하는 경우에만 Apple의 개별 앱 실행 안내를 확인하세요.
https://support.apple.com/en-us/102445
INSTALL

ditto -c -k --sequesterRsrc --keepParent "$app_dir" "$artifact_dir/$asset_name.app.zip"
hdiutil create -volname "ViveBrush $version" -srcfolder "$staging_dir/disk-image" \
    -ov -format UDZO "$artifact_dir/$asset_name.dmg"
hdiutil verify "$artifact_dir/$asset_name.dmg"
(
    cd "$artifact_dir"
    shasum -a 256 "$asset_name.dmg" "$asset_name.app.zip" > SHA256SUMS.txt
)
printf 'Packaged: %s\n' "$artifact_dir/$asset_name.dmg" \
    "$artifact_dir/$asset_name.app.zip" "$artifact_dir/SHA256SUMS.txt"
