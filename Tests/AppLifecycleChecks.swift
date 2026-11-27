import AppKit
import Carbon
import SwiftUI

@main
struct AppLifecycleChecks {
    struct Failure: Error { let message: String }

    @MainActor
    static func main() throws {
        try toolbarTopPaddingChecks()
        try keyActionChecks()
        try standbyAndReturnToStandbyChecks()
        print("PASS: toolbar padding, key actions, and standby lifecycle checks")
    }

    static func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw Failure(message: message) }
    }

    static func toolbarTopPaddingChecks() throws {
        let secondary = ContentView.toolbarTopPadding(
            screenFrame: CGRect(x: 1920, y: 0, width: 1920, height: 1080),
            visibleFrame: CGRect(x: 1920, y: 0, width: 1920, height: 1080),
            safeAreaTop: 0
        )
        try check(secondary == 28, "Secondary screen expected 28, got \(secondary)")

        let standardMenuBar = ContentView.toolbarTopPadding(
            screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 875),
            safeAreaTop: 0
        )
        try check(standardMenuBar == 37, "Standard menu bar expected 37, got \(standardMenuBar)")

        let notchedMacBook = ContentView.toolbarTopPadding(
            screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 944),
            safeAreaTop: 32
        )
        try check(notchedMacBook == 50, "Notched MacBook expected 50, got \(notchedMacBook)")

        let autoHideNotch = ContentView.toolbarTopPadding(
            screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            safeAreaTop: 32
        )
        try check(autoHideNotch == 44, "Auto-hide menu bar on notched MacBook expected 44, got \(autoHideNotch)")
    }

    @MainActor
    static func keyActionChecks() throws {
        try check(AppDelegate.keyAction(keyCode: kVK_Tab, modifiers: .option) == .toggleAnnotation,
                  "Option+Tab must toggle annotation")
        try check(AppDelegate.keyAction(keyCode: kVK_Escape, modifiers: []) == .exitAnnotation,
                  "Escape must exit annotation")
        try check(AppDelegate.keyAction(keyCode: kVK_ANSI_Q, modifiers: []) == .exitAnnotation,
                  "Q must exit annotation")
        try check(AppDelegate.keyAction(keyCode: kVK_ANSI_Z, modifiers: .command) == .undo,
                  "Cmd+Z must undo")
        try check(AppDelegate.keyAction(keyCode: kVK_Delete, modifiers: []) == .clear,
                  "Delete must clear")
        try check(AppDelegate.keyAction(keyCode: kVK_ForwardDelete, modifiers: []) == .clear,
                  "ForwardDelete must clear")

        try check(AppDelegate.keyAction(
            keyCode: kVK_Tab, modifiers: [.option, .capsLock, .numericPad, .function]
        ) == .toggleAnnotation, "Ignored modifier flags should be stripped for Option+Tab")
        try check(AppDelegate.keyAction(
            keyCode: kVK_ANSI_Q, modifiers: [.capsLock]
        ) == .exitAnnotation, "CapsLock should be stripped for Q")
        try check(AppDelegate.keyAction(
            keyCode: kVK_ANSI_Z, modifiers: [.command, .capsLock, .numericPad]
        ) == .undo, "CapsLock and numericPad should be stripped for Cmd+Z")
        try check(AppDelegate.keyAction(
            keyCode: kVK_ForwardDelete, modifiers: [.numericPad, .function]
        ) == .clear, "NumericPad and function should be stripped for ForwardDelete")

        try check(AppDelegate.keyAction(keyCode: kVK_ANSI_Q, modifiers: .command) == nil,
                  "Cmd+Q must be ignored by annotation key monitor")
        try check(AppDelegate.keyAction(keyCode: kVK_ANSI_Z, modifiers: .shift) == nil,
                  "Shift+Z must be ignored")
        try check(AppDelegate.keyAction(keyCode: kVK_ANSI_Z, modifiers: [.command, .shift]) == nil,
                  "Cmd+Shift+Z must be ignored")
        try check(AppDelegate.keyAction(keyCode: kVK_Tab, modifiers: []) == nil,
                  "Plain Tab must be ignored")
    }

    @MainActor
    static func standbyAndReturnToStandbyChecks() throws {
        let delegate = AppDelegate()
        try check(delegate.mode == .standby, "AppDelegate must start in .standby mode")

        delegate.drawing.selectColor(3)
        delegate.drawing.isColorRotationEnabled = true
        delegate.drawing.draw(at: CGPoint(x: 10, y: 20), start: .zero, on: 1)
        delegate.drawing.finishStroke()
        delegate.drawing.draw(at: CGPoint(x: 30, y: 40), start: CGPoint(x: 20, y: 20), on: 1)
        try check(!delegate.drawing.strokes.isEmpty && delegate.drawing.currentStroke != nil,
                  "Expected active strokes before returning to standby")

        delegate.returnToStandby()
        try check(delegate.mode == .standby, "Mode must remain .standby after returnToStandby()")
        try check(delegate.drawing.strokes.isEmpty && delegate.drawing.currentStroke == nil,
                  "returnToStandby() must clear strokes and in-progress stroke")
        try check(delegate.drawing.nextColorIndex == 4 && delegate.drawing.isColorRotationEnabled,
                  "returnToStandby() must preserve color rotation settings")

        delegate.returnToStandby(restoreFocus: false)
        try check(delegate.mode == .standby, "Repeated returnToStandby(restoreFocus: false) must remain .standby")
    }
}
