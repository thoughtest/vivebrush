import Sparkle
import SwiftUI

@MainActor
final class AppUpdater: NSObject, ObservableObject, SPUUpdaterDelegate {
    @Published private(set) var isBusy = false
    @Published private(set) var status = "업데이트 확인을 누르면 새 버전을 확인합니다."

    let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "개발 빌드"
    private var controller: SPUStandardUpdaterController!
    private var window: NSWindow?
    private var started = false

    override init() {
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
    }

    func showWindow() {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 480, height: 260),
                styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false
            )
            window.title = "ViveBrush 업데이트"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: UpdateSettingsView(updater: self))
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func checkForUpdates() {
        guard !isBusy else { return }
        guard let publicKey = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              Data(base64Encoded: publicKey)?.count == 32 else {
            status = "이 개발 빌드에서는 업데이트를 사용할 수 없습니다. 릴리즈 페이지를 확인하세요."
            return
        }
        guard !Bundle.main.bundleURL.path.hasPrefix("/Volumes/") else {
            status = "먼저 ViveBrush.app을 응용 프로그램 폴더로 옮겨 실행하세요."
            return
        }
        if !started {
            controller.startUpdater()
            started = true
        }
        guard controller.updater.canCheckForUpdates else {
            status = "업데이트를 준비하지 못했습니다. 창을 닫고 다시 시도하세요."
            return
        }
        isBusy = true
        status = "새 버전을 확인하고 있습니다…"
        controller.checkForUpdates(nil)
    }

    func feedURLString(for updater: SPUUpdater) -> String? {
        #if DEBUG
        if let address = ProcessInfo.processInfo.environment["VIVEBRUSH_TEST_FEED"],
           let url = URL(string: address), ["127.0.0.1", "localhost"].contains(url.host ?? "") {
            return address
        }
        #endif
        return Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        status = "새 버전 \(item.displayVersionString)을 사용할 수 있습니다. 업데이트 창에서 설치하세요."
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        isBusy = false
        if let error = error as NSError? {
            status = error.domain == SUSparkleErrorDomain && error.code == Int(SUError.noUpdateError.rawValue)
                ? "현재 최신 버전입니다. (\(currentVersion))" : error.localizedDescription
        } else {
            status = "업데이트 확인을 마쳤습니다."
        }
    }
}

private struct UpdateSettingsView: View {
    @ObservedObject var updater: AppUpdater

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("ViveBrush 업데이트", systemImage: "arrow.triangle.2.circlepath")
                .font(.title2.bold())
            Text("현재 버전 \(updater.currentVersion)").foregroundStyle(.secondary)
            Text(updater.status)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("updateStatus")
            Text("새 버전이 있으면 다운로드·설치 후 앱을 다시 시작할 수 있습니다.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                if updater.isBusy { ProgressView().controlSize(.small) }
                Button("업데이트 확인", action: updater.checkForUpdates)
                    .buttonStyle(.borderedProminent)
                    .disabled(updater.isBusy)
                Spacer()
                Link("릴리즈 보기", destination: URL(string: "https://github.com/thoughtest/vivebrush/releases")!)
            }
        }
        .padding(24)
        .frame(width: 440)
    }
}
