import Sparkle
import SwiftUI

@MainActor
final class AppUpdater: NSObject, ObservableObject, SPUUpdaterDelegate {
    @Published private(set) var isBusy = false
    @Published private(set) var status = "업데이트 확인을 누르면 새 버전을 확인합니다."

    let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "개발 빌드"
    let currentBuild = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    private var controller: SPUStandardUpdaterController!
    private var window: NSWindow?
    private var started = false
    private var completionStatus = "업데이트 확인을 마쳤습니다."

    override init() {
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
    }

    func showWindow() {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 480, height: 310),
                styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false
            )
            window.title = "ViveBrush 업데이트"
            window.isReleasedWhenClosed = false
            let hostingView = NSHostingView(rootView: UpdateSettingsView(updater: self))
            hostingView.sizingOptions = []
            window.contentView = hostingView
            window.setContentSize(NSSize(width: 480, height: 310))
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
        guard let address = feedURLString(for: controller.updater), Self.isValidFeedURL(address) else {
            status = "업데이트 서버 주소가 설정되지 않았습니다. 릴리즈 페이지를 확인하세요."
            return
        }
        guard !Bundle.main.bundleURL.path.hasPrefix("/Volumes/") else {
            status = "먼저 ViveBrush.app을 응용 프로그램 폴더로 옮겨 실행하세요."
            return
        }
        if !started {
            do {
                try controller.updater.start()
                started = true
            } catch {
                status = "업데이트를 준비하지 못했습니다. \(error.localizedDescription)"
                return
            }
        }
        guard controller.updater.canCheckForUpdates else {
            status = "업데이트를 준비하지 못했습니다. 창을 닫고 다시 시도하세요."
            return
        }
        isBusy = true
        completionStatus = "업데이트 확인을 마쳤습니다."
        status = "새 버전을 확인하고 있습니다…"
        controller.checkForUpdates(nil)
    }

    static func isValidFeedURL(_ address: String) -> Bool {
        guard let url = URLComponents(string: address),
              let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil, url.fragment == nil else { return false }
        if url.scheme == "https" { return true }
        #if DEBUG
        return url.scheme == "http" && ["127.0.0.1", "localhost"].contains(host)
        #else
        return false
        #endif
    }

    func feedURLString(for updater: SPUUpdater) -> String? {
        #if DEBUG
        if let address = ProcessInfo.processInfo.environment["VIVEBRUSH_TEST_FEED"],
           let url = URL(string: address), ["127.0.0.1", "localhost"].contains(url.host ?? ""),
           Self.isValidFeedURL(address) {
            return address
        }
        #endif
        return Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        status = "새 버전 \(item.displayVersionString)을 사용할 수 있습니다. 업데이트 창에서 설치하세요."
        completionStatus = "새 버전 \(item.displayVersionString)의 설치를 미뤘습니다. 업데이트 확인을 눌러 다시 설치할 수 있습니다."
    }

    func updater(_ updater: SPUUpdater, willDownloadUpdate item: SUAppcastItem, with request: NSMutableURLRequest) {
        status = "새 버전 \(item.displayVersionString)을 다운로드하고 있습니다…"
    }

    func userDidCancelDownload(_ updater: SPUUpdater) {
        completionStatus = "다운로드를 취소했습니다. 업데이트 확인을 눌러 다시 시도할 수 있습니다."
    }

    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        status = "새 버전 \(item.displayVersionString)을 설치하고 앱을 다시 시작합니다…"
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        isBusy = false
        if let error = error as NSError? {
            status = Self.message(for: error, currentVersion: currentVersion)
        } else {
            status = completionStatus
        }
    }

    static func message(for error: NSError, currentVersion: String) -> String {
        guard error.domain == SUSparkleErrorDomain else { return error.localizedDescription }
        switch error.code {
        case Int(SUError.noUpdateError.rawValue):
            let reason = (error.userInfo[SPUNoUpdateFoundReasonKey] as? NSNumber)?.intValue ?? -1
            if reason == Int(SPUNoUpdateFoundReason.systemIsTooOld.rawValue) ||
                reason == Int(SPUNoUpdateFoundReason.systemIsTooNew.rawValue) ||
                reason == Int(SPUNoUpdateFoundReason.hardwareDoesNotSupportARM64.rawValue) {
                return "이 Mac에서 설치할 수 있는 새 버전이 없습니다. \(error.localizedDescription)"
            }
            return "현재 최신 버전입니다. (\(currentVersion))"
        case Int(SUError.signatureError.rawValue), Int(SUError.validationError.rawValue):
            return "업데이트 서명을 확인할 수 없어 중단했습니다. 잠시 후 다시 확인하거나 릴리즈 페이지를 확인하세요."
        case Int(SUError.appcastParseError.rawValue):
            return "업데이트 정보를 검증하지 못해 중단했습니다. 잠시 후 다시 확인하거나 릴리즈 페이지를 확인하세요."
        case Int(SUError.appcastError.rawValue), Int(SUError.downloadError.rawValue):
            return "업데이트 서버에 연결하지 못했습니다. 인터넷 연결을 확인한 뒤 다시 시도하세요. 릴리즈 페이지에서도 다운로드할 수 있습니다."
        case Int(SUError.installationCanceledError.rawValue):
            return "업데이트 설치를 취소했습니다. 다시 시도할 수 있습니다."
        case Int(SUError.runningFromDiskImageError.rawValue), Int(SUError.runningTranslocated.rawValue):
            return "ViveBrush.app을 응용 프로그램 폴더로 옮긴 뒤 다시 실행하세요."
        default:
            return error.localizedDescription
        }
    }
}

private struct UpdateSettingsView: View {
    @ObservedObject var updater: AppUpdater

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("ViveBrush 업데이트", systemImage: "arrow.triangle.2.circlepath")
                .font(.title2.bold())
            Text("현재 버전 \(updater.currentVersion) (빌드 \(updater.currentBuild))").foregroundStyle(.secondary)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(24)
    }
}
