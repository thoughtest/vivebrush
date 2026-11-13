# ViveBrush

실시간 macOS 화면 위에 투명한 창을 올려 선택한 색으로 자유롭게 판서하는 Swift / SwiftUI 앱입니다. 업데이트 확인·설치에는 [Sparkle](https://sparkle-project.org/) 프레임워크를 사용합니다.

## 개발 및 서명 상태

현재 버전은 **v0.2.0 / 빌드 4**입니다. 소스와 릴리즈는 공개 저장소에서 제공하며, 업데이트 확인에 GitHub 로그인이 필요하지 않습니다. 앱 내 업데이트 확인·다운로드·설치·재시작과 수동 색 선택을 지원합니다. 변경 사항은 [릴리즈 노트](RELEASE_NOTES.md)를 확인하세요.

이 프로젝트는 개인 Mac에서 다음 두 종류의 서명을 사용합니다.

- **앱 번들**: Apple Developer 계정 없이 가능한 ad-hoc 서명. Developer ID 서명 및 Apple 공증은 포함하지 않습니다.
- **업데이트 ZIP과 피드**: 개인 Mac 키체인의 Ed25519 키로 서명. 앱에는 검증용 공개 키만 들어가며 개인 키는 저장소나 패키지에 포함하지 않습니다.

```sh
swift package resolve
./scripts/test.sh
./scripts/run.sh
```

이미 배포에 사용하는 키가 있다면 새 키를 만들지 말고 원래 키를 가져와야 합니다. 배포 담당 개인 Mac에서 키를 처음 설정하거나 기존 키와 공개 키가 일치하는지 확인할 때만 아래 명령을 사용하세요.

```sh
./scripts/setup-update-key.sh --personal-mac
```

빌드와 테스트, 배포본 검증에는 개인 키가 필요하지 않습니다. ZIP과 피드 **서명**에만 키체인 접근이 필요하며, 시스템 요청 창에 로그인 암호를 직접 입력해 허용합니다. 배포 키를 잃으면 기존 설치본에 업데이트를 제공할 수 없으므로 안전한 별도 백업이 필요합니다. 키를 다른 Mac으로 옮기는 절차는 [Sparkle 배포 문서](https://sparkle-project.org/documentation/publishing/)를 참고하세요.

## Apple Silicon 릴리즈 설치

[GitHub Releases](https://github.com/thoughtest/vivebrush/releases)에서 **arm64** 패키지를 받으세요. 로그인 없이 다운로드할 수 있습니다.

- **`.dmg`**: 열어서 `ViveBrush.app`을 `Applications` 폴더로 드래그한 뒤 실행합니다.
- **`.app.zip`**: 압축을 풀면 `ViveBrush.app`이 나옵니다. 응용 프로그램 폴더로 옮긴 뒤 실행합니다.
- **`SHA256SUMS.txt`**: DMG, APP ZIP, 서명된 업데이트 피드의 SHA-256 체크섬입니다.

대상은 **Apple Silicon (M1 이상), macOS 14 이상**이며 Intel Mac용 바이너리는 포함하지 않습니다. 설치 후에는 Xcode나 Swift가 필요하지 않습니다.

현재 패키지는 **ad-hoc 서명한 테스트 빌드**이며 Developer ID 서명과 Apple 공증을 포함하지 않습니다. 처음 실행할 때 macOS에서 개발자를 확인할 수 없다는 경고가 표시될 수 있습니다. 출처와 파일을 신뢰하는 경우 시스템 설정 → 개인정보 보호 및 보안에서 해당 앱의 **확인 없이 열기(Open Anyway)**를 선택할 수 있습니다. 자세한 동작은 [Apple의 앱 실행 안내](https://support.apple.com/en-us/102445)를 확인하세요. 공증된 배포본을 만들려면 [Developer ID 서명과 Apple 공증](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)이 필요합니다.

## 앱에서 업데이트

연필 메뉴 → **업데이트 확인…**에서 현재 버전을 보고 **업데이트 확인**을 누르세요. 새 버전이 있으면 다운로드·설치·재시작을 진행할 수 있습니다. 최신 버전이면 해당 사실을 표시하고, 다운로드 취소와 설치 연기도 업데이트 창에서 처리합니다. 사용자가 확인하기 전에는 자동으로 다운로드하거나 설치하지 않습니다.

업데이트는 공개 저장소의 `updates/appcast.xml`과 공개 릴리즈 파일을 사용하므로 **GitHub 토큰이나 로그인은 필요하지 않습니다**. 업데이트 정보와 ZIP은 Ed25519 서명으로 검증하며, 변조되거나 서명이 없는 파일은 설치하지 않습니다. 이 서명은 Apple 공증과 별개입니다.

v0.1.0에는 업데이트 기능이 없으므로 업데이트 기능이 포함된 다음 배포본을 한 번 직접 설치해야 합니다. 이후 버전부터 앱 안에서 업데이트할 수 있습니다. DMG 안에서 실행 중이라면 앱을 응용 프로그램 폴더로 먼저 옮기세요.

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
./scripts/test.sh           # 드로잉, 업데이트 설정·오류 처리, 오래된 패키지 차단 검증
./scripts/package.sh        # Apple Silicon용 DMG, APP ZIP, 체크섬 생성
./scripts/verify-release.sh # 피드 생성 후 공개 키로 서명·체크섬·앱 번들 검증
```

배포 파일은 `dist/<버전>/`에 생성됩니다. 패키징은 별도 `build/arm64/ViveBrush.app`을 사용하므로 기본 개발 앱이 실행 중이어도 가능합니다. `./scripts/build.sh release arm64`로 arm64 앱 번들만 만들 수도 있습니다. 패키지 버전은 `Resources/Info.plist`의 `CFBundleShortVersionString`을 따릅니다.

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

**자동 색상은 기본적으로 꺼져 있습니다.** 상단 도구 모음에서 색상 원을 클릭하면 해당 색으로 계속 그립니다. 흰 테두리는 다음 선에 사용할 색을 나타냅니다.

도구 모음이나 연필 메뉴의 **자동 색상**을 켜면 선 하나를 마칠 때마다 **빨강 → 주황 → 노랑 → 초록 → 파랑 → 보라** 순서로 바뀝니다. 끄면 현재 선택된 색으로 고정됩니다. 선 하나는 마우스를 누른 순간부터 뗄 때까지이며, 클릭만 해도 점 하나를 그립니다. 이미 그린 선의 색은 옵션을 바꿔도 유지됩니다.

실행 취소·모두 지우기·판서 종료 후 다시 시작해도 선택한 색과 자동 색상 옵션을 유지합니다. 앱을 새로 실행하면 빨강·자동 색상 끄기로 시작합니다.

## 동작과 파일 구성

- [ViveBrushApp.swift](Sources/ViveBrush/ViveBrushApp.swift): 메뉴 막대 앱, 전역 토글, 키 입력, 투명 NSWindow와 모드 전환.
- [ContentView.swift](Sources/ViveBrush/ContentView.swift): 투명 SwiftUI Canvas, 선·색상 상태, 간단한 도구 모음.
- [AppUpdater.swift](Sources/ViveBrush/AppUpdater.swift): 업데이트 창과 Sparkle 연결. 토큰을 읽거나 저장하지 않습니다.
- [Info.plist](Resources/Info.plist): 앱 번들 식별자, 최소 OS, `LSUIElement` 설정.
- [scripts](scripts): Swift Package를 빌드하고 실행 가능한 `.app`으로 포장하는 스크립트.

연결된 화면마다 전체 `NSScreen.frame` 크기의 투명한 창을 만들며 메뉴 막대·Dock 영역도 덮습니다. 창에는 선과 도구 모음만 그리며 밑의 화면은 실시간으로 보입니다. 여러 화면의 선은 하나의 그리기 순서로 실행 취소됩니다. 디스플레이 구성이 바뀌면 판서를 종료합니다.

오버레이는 `.borderless`, `.clear`, `isOpaque = false`, `hasShadow = false`, `.screenSaver` 레벨을 사용합니다. 판서 시 `ignoresMouseEvents = false`로 입력을 받고, 대기 전환 시 `true`로 설정한 후 창을 숨깁니다. 대기 중 전역 토글 외의 키와 마우스 입력은 다른 앱으로 전달됩니다.

## Xcode에서 열거나 별도 프로젝트로 옮길 때

`Package.swift`를 Xcode로 열 수 있습니다. 메뉴 막대 앱으로 실행하려면 위 스크립트로 생성한 `.app`을 사용하세요.

새 macOS App 프로젝트에 `Sources/ViveBrush`의 Swift 파일을 넣는 경우 다음을 설정하세요.

1. Deployment Target: **macOS 14.0 이상**.
2. Signing & Capabilities: **App Sandbox 제거 / 비활성화**. 스크립트 빌드는 Sandbox를 사용하지 않습니다.
3. Info: **Application is agent (UIElement) = YES** (`LSUIElement`). Dock 아이콘 없이 메뉴 막대에서 실행됩니다.
4. 기존 자동 생성 `@main App` 파일은 제거하고, Bundle Identifier를 **com.vivebrush.app**으로 유지하세요.
5. 화면 녹화 권한은 필요하지 않습니다. 전역 토글은 Carbon `RegisterEventHotKey`로 처리하므로 별도의 접근성 권한도 요구하지 않습니다.
6. Sparkle 2.10.1 패키지를 추가하고 프레임워크를 Embed & Sign으로 포함하세요. 제공된 `Info.plist`의 `SUFeedURL`, `SUPublicEDKey`, 서명 검증 설정도 유지하세요. 저장소의 빌드 스크립트는 프레임워크 복사와 앱 서명을 처리합니다.

## 업데이트 배포

1. `Info.plist`의 표시 버전과 빌드 번호를 모두 올립니다. 빌드 번호는 항상 증가해야 합니다.
2. `./scripts/package.sh`로 arm64 앱과 패키지를 생성합니다.
3. `./scripts/create-appcast.sh 'https://github.com/thoughtest/vivebrush/releases/download/v<버전>/ViveBrush-<버전>-arm64.app.zip'`로 ZIP과 업데이트 피드에 서명합니다. 결과는 `dist/<버전>/appcast.xml`입니다.
4. `./scripts/verify-release.sh`로 실제 ZIP 내부의 버전·공개 키, ZIP/피드 서명, 체크섬, arm64 앱 코드 서명을 검증합니다. 개인 키나 키체인 접근 없이 실행됩니다. 소스 설정과 패키지가 다르면 피드 생성과 검증 모두 중단하므로 먼저 다시 패키징하세요.
5. 해당 버전의 태그와 GitHub 릴리즈를 만들고 DMG, APP ZIP, `appcast.xml`, `SHA256SUMS.txt`를 업로드합니다.
6. 게시한 파일을 검증한 뒤 서명된 `appcast.xml`을 `updates/appcast.xml`로 그대로 복사하여 main에 커밋·push합니다. 서명 후 XML 내용을 편집하면 서명이 무효화됩니다.

업데이트 서명 개인 키는 개인 배포 담당 Mac 키체인의 `com.vivebrush.app.updates` 계정으로 보관합니다. 저장소와 앱에는 공개 키만 포함합니다. 배포가 시작된 뒤에는 개인 키를 잃으면 기존 설치본에 대한 업데이트 서명을 만들 수 없으므로 안전하게 백업해야 합니다. 배포 이후 다른 Mac으로 옮길 때는 새 키로 교체하지 말고 원래 키를 Sparkle 도구로 가져오세요. 자세한 절차는 [Sparkle 배포 문서](https://sparkle-project.org/documentation/publishing/)를 참고하세요.

배포 파일에 서명할 때는 macOS가 `sign_update`의 키체인 접근을 요청할 수 있습니다. 배포 담당자가 Mac 로그인 암호를 해당 시스템 창에 직접 입력해 허용합니다. 앱을 설치하거나 업데이트하는 사용자에게는 이 서명 개인 키와 키체인 암호가 필요하지 않습니다.

## 검증

`./scripts/test.sh`는 드로잉·투명 배경 8개 검사, Debug/Release 양쪽의 업데이트 주소·상태 메시지 검사, 오래된 패키지와 잘못된 다운로드 주소를 차단하는 5개 회귀 테스트를 실행합니다.

개인 Mac에서 실제 서명 키와 로컬 HTTP 피드로 최신 버전 안내, 변조된 피드 차단, 설치 연기 후 재시도, **0.1.99 / 빌드 2 → 0.2.0 / 빌드 4 다운로드·설치·재시작**을 확인했습니다. 로컬 HTTP 피드 지정은 Debug 빌드의 `VIVEBRUSH_TEST_FEED` 환경 변수로만 허용하며 Release 빌드는 HTTPS 피드를 사용합니다. 테스트용 앱과 피드는 `build/`에만 생성하고 배포하지 않습니다.

`./scripts/verify-release.sh`는 개인 키 없이 공개 키로 ZIP과 피드의 Ed25519 서명, 체크섬, 패키지 내부 버전·키, arm64 아키텍처, 앱 코드 서명을 검증합니다. `./scripts/verify-release.sh /path/to/downloaded-assets`로 다운로드한 릴리즈도 검증할 수 있습니다.

## 수동 확인

1. 대기 모드에서 다른 앱 클릭·드래그·키 입력이 동작하는지 확인합니다.
2. 시계나 동영상이 보이는 상태에서 `⌥Tab`을 눌러 판서 중에도 배경이 계속 움직이는지 확인합니다.
3. 기본 상태에서 여러 선을 그려 모두 빨강인지 확인합니다. 파랑색 원을 선택하면 계속 파랑으로 그려지는지 확인합니다. 자동 색상을 켜고 선을 그려 여섯 색의 순환을 확인한 뒤, 다시 끄면 색이 고정되는지 확인합니다.
4. `⌘Z`로 마지막 선만 지웁니다. Delete와 Backspace로 모두 지워도 선택한 색과 자동 색상 옵션이 유지되는지 확인합니다.
5. Esc, Q, 전역 토글, 완료 버튼으로 각각 종료하고 밑의 앱 조작이 복구되는지 확인합니다.
6. 여러 모니터·Retina·전체 화면 앱에서도 배경이 그대로 보이며 마우스 위치에 선이 그려지는지 확인합니다.
