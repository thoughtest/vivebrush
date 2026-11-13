import Carbon
import OSLog
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

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    enum Mode { case standby, annotating }

    @Published private(set) var mode: Mode = .standby
    @Published private(set) var hotKeyLabel = "⌥Tab"
    let drawing = DrawingState()
    let updater = AppUpdater()

    private var windows: [NSWindow] = []
    private var keyMonitor: Any?
    private var hotKey: EventHotKeyRef?
    private var hotKeyHandler: EventHandlerRef?
    private var previousApplication: NSRunningApplication?
    private let logger = Logger(subsystem: "com.vivebrush.app", category: "Lifecycle")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        registerHotKey()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let handled = MainActor.assumeIsolated {
                guard let self, self.mode != .standby else { return false }
                let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                    .subtracting([.capsLock, .numericPad, .function])
                switch (Int(event.keyCode), modifiers) {
                case (kVK_Tab, .option): self.toggleAnnotation()
                case (kVK_Escape, []), (kVK_ANSI_Q, []): self.returnToStandby()
                case (kVK_ANSI_Z, .command): self.drawing.undo()
                case (kVK_Delete, []), (kVK_ForwardDelete, []):
                    self.drawing.clear()
                default: return false
                }
                return true
            }
            return handled ? nil : event
        }
        NotificationCenter.default.addObserver(
            self, selector: #selector(screenConfigurationChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil
        )
        if ProcessInfo.processInfo.arguments.contains("--annotate") { toggleAnnotation() }
        if ProcessInfo.processInfo.arguments.contains("--updates") {
            DispatchQueue.main.async { self.updater.showWindow() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        returnToStandby(restoreFocus: false)
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let hotKeyHandler { RemoveEventHandler(hotKeyHandler) }
        NotificationCenter.default.removeObserver(self)
    }

    func toggleAnnotation() {
        guard mode == .standby else {
            returnToStandby()
            return
        }
        previousApplication = NSWorkspace.shared.frontmostApplication
        showOverlays()
    }

    func returnToStandby(restoreFocus: Bool = true) {
        logger.info("Returning to standby")
        let wasAnnotating = mode == .annotating
        for window in windows {
            window.ignoresMouseEvents = true
            window.orderOut(nil)
            window.close()
        }
        windows.removeAll()
        drawing.clear()
        mode = .standby
        if restoreFocus, wasAnnotating,
           let previousApplication,
           previousApplication.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApplication.activate(options: [])
        }
        previousApplication = nil
    }

    private func showOverlays() {
        drawing.clear()
        for screen in NSScreen.screens {
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                continue
            }
            let window = OverlayWindow(
                contentRect: screen.frame, styleMask: .borderless,
                backing: .buffered, defer: false
            )
            window.isReleasedWhenClosed = false
            window.title = "ViveBrush — 판서"
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = false
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.animationBehavior = .none
            window.ignoresMouseEvents = false
            window.acceptsMouseMovedEvents = true
            let hostingView = NSHostingView(rootView: ContentView(
                drawing: drawing, displayID: number.uint32Value,
                onExit: { [weak self] in self?.returnToStandby() }
            ))
            hostingView.safeAreaRegions = []
            window.contentView = hostingView
            window.setFrame(screen.frame, display: false)
            windows.append(window)
        }
        guard !windows.isEmpty else {
            previousApplication = nil
            return
        }
        mode = .annotating
        NSApp.activate(ignoringOtherApps: true)
        windows.forEach { $0.orderFrontRegardless() }
        let mouse = NSEvent.mouseLocation
        (windows.first { $0.frame.contains(mouse) } ?? windows.first)?.makeKeyAndOrderFront(nil)
        logger.info("Annotation active on \(self.windows.count) displays")
    }

    private func registerHotKey() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)
        )
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(), { _, _, context in
                guard let context else { return OSStatus(eventNotHandledErr) }
                let delegate = Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue()
                MainActor.assumeIsolated { delegate.toggleAnnotation() }
                return noErr
            }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &hotKeyHandler
        )
        guard handlerStatus == noErr else {
            hotKeyLabel = "등록 실패 — 메뉴에서 시작"
            return
        }
        let identifier = EventHotKeyID(signature: 0x56425253, id: 1) // VBRS
        let status = RegisterEventHotKey(
            UInt32(kVK_Tab), UInt32(optionKey), identifier,
            GetApplicationEventTarget(), 0, &hotKey
        )
        if status != noErr {
            // ScreenBrush or another utility may already own Option-Tab.
            let fallbackStatus = RegisterEventHotKey(
                UInt32(kVK_Tab), UInt32(controlKey | optionKey), identifier,
                GetApplicationEventTarget(), 0, &hotKey
            )
            hotKeyLabel = fallbackStatus == noErr ? "⌃⌥Tab (⌥Tab 사용 중)" : "등록 실패 — 메뉴에서 시작"
        }
        logger.info("Global shortcut: \(self.hotKeyLabel, privacy: .public)")
    }

    @objc private func screenConfigurationChanged() {
        if mode != .standby { returnToStandby() }
    }
}

private final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
