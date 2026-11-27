import SwiftUI

@main
struct ViveBrushApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("ViveBrush", systemImage: "pencil.tip.crop.circle") {
            Button(appDelegate.mode == .standby ? "판서 시작" : "판서 종료") {
                appDelegate.toggleAnnotation()
            }
            Text("전역 단축키: \(appDelegate.hotKeyLabel)")
            Divider()
            ColorRotationToggle(drawing: appDelegate.drawing)
            Divider()
            Button("업데이트 확인…") {
                appDelegate.returnToStandby()
                appDelegate.updater.showWindow()
            }
            Divider()
            Text("⌘Z 실행 취소 · Delete 모두 지우기")
            Text("Esc / Q 판서 종료")
            Divider()
            Button("ViveBrush 종료") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}
