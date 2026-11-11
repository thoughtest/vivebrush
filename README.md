# ViveBrush

실시간 macOS 화면 위에 투명한 창을 올려 무지개 색으로 자유롭게 판서하는 Swift / SwiftUI MVP입니다. 외부 의존성 없이 앱 코드는 Swift 파일 두 개로 구성했습니다.

## 바로 실행

macOS 14 Sonoma 이상, Swift 5.9 이상의 Command Line Tools 또는 Xcode가 필요합니다.

```sh
# Command Line Tools가 없다면 먼저 설치
xcode-select --install

# 저장소 폴더에서 빌드하고 실행
./scripts/run.sh
```

메뉴 막대의 연필 아이콘이 나타나면 실행 중입니다. 처음에는 대기 모드이므로 다른 앱을 그대로 조작할 수 있습니다. `⌥Tab` 또는 연필 메뉴의 **판서 시작**을 누르세요.

화면을 캡처하지 않으므로 **화면 녹화 권한이 필요하지 않습니다**. 판서 중에도 밑의 화면·동영상은 계속 갱신됩니다. 다른 앱을 클릭하거나 조작하려면 판서를 종료해 대기 모드로 전환하세요.

Cursor / Windsurf에서는 폴더를 열고 **Terminal → Run Task → ViveBrush: Run**을 선택하세요. 기본 빌드는 `⇧⌘B`입니다. Swift 확장 프로그램은 코드 편집에 권장되며 터미널 실행에는 필요하지 않습니다.

```sh
./scripts/build.sh          # build/ViveBrush.app 생성
./scripts/run.sh release    # 최적화 빌드 후 실행
./scripts/test.sh           # 드로잉 상태·투명 배경 검증 (Xcode / XCTest 불필요)
```

앱이 종료된 상태라면 `open build/ViveBrush.app --args --annotate`로 실행 직후 판서를 시작할 수도 있습니다.

업데이트 빌드를 실행하려면 먼저 기존 앱의 연필 메뉴에서 **ViveBrush 종료**를 선택하세요. `open`은 이미 실행 중인 앱을 새 바이너리로 교체하지 않습니다. 로컬 빌드는 ad-hoc 서명이며 배포용 공증은 포함하지 않습니다.

## 조작

| 입력 | 동작 |
| --- | --- |
| `Option + Tab` | 대기 ↔ 판서 전환 |
| 마우스 드래그 | 자유롭게 선 그리기 |
| `Command + Z` | 마지막 선 하나 실행 취소 |
| `Delete` / `Backspace` / `Fn + Delete` | 모든 선 지우기 |
| `Escape` / `Q` | 판서 종료, 대기 모드 복귀 |

`⌥Tab`을 다른 앱이 사용 중이면 전역 단축키를 `⌃⌥Tab`으로 등록하며 현재 단축키는 연필 메뉴에 표시합니다. 둘 다 등록할 수 없어도 메뉴에서 전환할 수 있습니다. 실행 취소·지우기·종료 키는 판서 앱이 활성화된 동안만 처리합니다. 한글 입력 상태에서도 물리 키 위치로 동작합니다.

선 하나는 마우스를 누른 순간부터 뗄 때까지입니다. 색은 **빨강 → 주황 → 노랑 → 초록 → 파랑 → 보라** 순서로 바뀌고 여섯 색을 반복합니다. 클릭만 해도 점 하나를 그립니다. 실행 취소는 색 순서를 되돌리지 않으며, 모두 지우기와 새 판서 세션은 빨강부터 시작합니다. 상단 도구 모음의 흰 테두리가 다음 선 색입니다.

## 동작과 파일 구성

- [ViveBrushApp.swift](Sources/ViveBrush/ViveBrushApp.swift): 메뉴 막대 앱, 전역 토글, 키 입력, 투명 NSWindow와 모드 전환.
- [ContentView.swift](Sources/ViveBrush/ContentView.swift): 투명 SwiftUI Canvas, 선·색상 상태, 간단한 도구 모음.
- [Info.plist](Resources/Info.plist): 앱 번들 식별자, 최소 OS, `LSUIElement` 설정.
- [scripts](scripts): Swift Package를 빌드하고 실행 가능한 `.app`으로 포장하는 스크립트.

연결된 화면마다 전체 `NSScreen.frame` 크기의 투명한 창을 만들며 메뉴 막대·Dock 영역도 덮습니다. 창에는 선과 도구 모음만 그리며 밑의 화면은 실시간으로 보입니다. 여러 화면의 선은 하나의 그리기 순서로 실행 취소됩니다. 디스플레이 구성이 바뀌면 판서를 종료합니다.

오버레이는 `.borderless`, `.clear`, `isOpaque = false`, `hasShadow = false`, `.screenSaver` 레벨을 사용합니다. 판서 시 `ignoresMouseEvents = false`로 입력을 받고, 대기 전환 시 `true`로 설정한 후 창을 숨깁니다. 대기 중 전역 토글 외의 키와 마우스 입력은 다른 앱으로 전달됩니다.

## Xcode에서 열거나 별도 프로젝트로 옮길 때

`Package.swift`를 Xcode로 열 수 있습니다. 메뉴 막대 앱으로 실행하려면 위 스크립트로 생성한 `.app`을 사용하세요.

새 macOS App 프로젝트에 Swift 파일 두 개를 넣는 경우 다음을 설정하세요.

1. Deployment Target: **macOS 14.0 이상**.
2. Signing & Capabilities: **App Sandbox 제거 / 비활성화**. 스크립트 빌드는 Sandbox를 사용하지 않습니다.
3. Info: **Application is agent (UIElement) = YES** (`LSUIElement`). Dock 아이콘 없이 메뉴 막대에서 실행됩니다.
4. 기존 자동 생성 `@main App` 파일은 제거하고, Bundle Identifier를 **com.vivebrush.app**으로 유지하세요.
5. 화면 녹화 권한은 필요하지 않습니다. 전역 토글은 Carbon `RegisterEventHotKey`로 처리하므로 별도의 접근성 권한도 요구하지 않습니다.

## 수동 확인

1. 대기 모드에서 다른 앱 클릭·드래그·키 입력이 동작하는지 확인합니다.
2. 시계나 동영상이 보이는 상태에서 `⌥Tab`을 눌러 판서 중에도 배경이 계속 움직이는지 확인합니다.
3. 선 7개를 그려 여섯 색과 빨강 반복을 확인합니다. `⌘Z`로 마지막 선만 지웁니다.
4. Delete와 Backspace로 모두 지운 뒤 첫 선이 빨강인지 확인합니다.
5. Esc, Q, 전역 토글, 완료 버튼으로 각각 종료하고 밑의 앱 조작이 복구되는지 확인합니다.
6. 여러 모니터·Retina·전체 화면 앱에서도 배경이 그대로 보이며 마우스 위치에 선이 그려지는지 확인합니다.
