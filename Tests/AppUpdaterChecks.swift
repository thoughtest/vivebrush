import Foundation
import Sparkle

@main
struct AppUpdaterChecks {
    @MainActor
    static func main() {
        precondition(AppUpdater.isValidFeedURL("https://example.com/appcast.xml"))
        for invalid in ["", "https:", "file:///tmp/appcast.xml", "http://example.com/appcast.xml",
                        "https://user:password@example.com/appcast.xml", "https://@example.com/feed",
                        "https://example.com/feed#fragment"] {
            precondition(!AppUpdater.isValidFeedURL(invalid), "Accepted unsafe feed: \(invalid)")
        }
        #if DEBUG
        precondition(AppUpdater.isValidFeedURL("http://127.0.0.1:8765/appcast.xml"))
        #else
        precondition(!AppUpdater.isValidFeedURL("http://127.0.0.1:8765/appcast.xml"))
        #endif
        func message(_ code: SUError, info: [String: Any] = [:]) -> String {
            AppUpdater.message(for: NSError(domain: SUSparkleErrorDomain, code: Int(code.rawValue), userInfo: info),
                               currentVersion: "0.2.0")
        }
        precondition(message(.noUpdateError).contains("최신 버전"))
        precondition(message(.noUpdateError, info: [SPUNoUpdateFoundReasonKey: NSNumber(value:
            SPUNoUpdateFoundReason.systemIsTooOld.rawValue)]).contains("설치할 수 있는"))
        precondition(message(.signatureError).contains("서명"))
        precondition(message(.appcastParseError).contains("검증"))
        precondition(message(.downloadError).contains("다시 시도"))
        precondition(message(.installationCanceledError).contains("취소"))
        precondition(message(.runningTranslocated).contains("응용 프로그램"))
        let unknown = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "test error"])
        precondition(AppUpdater.message(for: unknown, currentVersion: "0.2.0") == "test error")
        checkConfigurationValidation()
        print("PASS: updater feed validation, configuration checks, and result/error messages")
    }

    @MainActor
    private static func checkConfigurationValidation() {
        let validKey = Data(repeating: 0x42, count: 32).base64EncodedString()
        let validFeed = "https://example.com/appcast.xml"
        let appPath = "/Applications/ViveBrush.app"
        let missingKeyMessage = "이 개발 빌드에서는 업데이트를 사용할 수 없습니다. 릴리즈 페이지를 확인하세요."
        let invalidFeedMessage = "업데이트 서버 주소가 설정되지 않았습니다. 릴리즈 페이지를 확인하세요."
        let volumesMessage = "먼저 ViveBrush.app을 응용 프로그램 폴더로 옮겨 실행하세요."

        precondition(
            AppUpdater.configurationError(publicKey: nil, feedURL: validFeed, bundlePath: appPath) == missingKeyMessage,
            "Missing public key must fail configuration validation"
        )
        for badKey in ["", "not-base64!", Data(repeating: 0x42, count: 16).base64EncodedString()] {
            precondition(
                AppUpdater.configurationError(
                    publicKey: badKey, feedURL: validFeed, bundlePath: appPath
                ) == missingKeyMessage,
                "Invalid public key must fail configuration validation: \(badKey)"
            )
        }
        for badFeed in [nil, "", "http://example.com/appcast.xml"] as [String?] {
            precondition(
                AppUpdater.configurationError(
                    publicKey: validKey, feedURL: badFeed, bundlePath: appPath
                ) == invalidFeedMessage,
                "Invalid feed URL must fail configuration validation"
            )
        }
        let localFeedError = AppUpdater.configurationError(
            publicKey: validKey,
            feedURL: "http://localhost:8765/appcast.xml",
            bundlePath: appPath
        )
        #if DEBUG
        precondition(localFeedError == nil, "Localhost feed should be accepted in DEBUG")
        #else
        precondition(localFeedError == invalidFeedMessage, "Localhost feed must be rejected in Release")
        #endif
        precondition(
            AppUpdater.configurationError(
                publicKey: validKey,
                feedURL: validFeed,
                bundlePath: "/Volumes/ViveBrush/ViveBrush.app"
            ) == volumesMessage,
            "Disk image bundle path must fail configuration validation"
        )
        precondition(
            AppUpdater.configurationError(publicKey: validKey, feedURL: validFeed, bundlePath: appPath) == nil,
            "Valid updater configuration must pass"
        )
    }
}
