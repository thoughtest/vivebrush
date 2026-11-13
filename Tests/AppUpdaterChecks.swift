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
        print("PASS: updater feed validation and result/error messages")
    }
}
