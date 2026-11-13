import SwiftUI

// A standalone runner keeps checks usable with Command Line Tools (no XCTest/Xcode).
@main
struct DrawingStateChecks {
    struct Failure: Error { let message: String }

    @MainActor
    static func main() throws {
        try fixedColorByDefault()
        try colorRotation()
        try toggleDuringStroke()
        try undoAcrossDisplays()
        try clearWhileDrawing()
        try cancelledGestureDoesNotReturn()
        try singleClick()
        try transparentBackground()
        print("PASS: 8 checks (fixed color default, color rotation, toggle, undo, clear, cancelled gesture, single click, transparency)")
    }

    static func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw Failure(message: message) }
    }

    @MainActor
    static func fixedColorByDefault() throws {
        let drawing = DrawingState()
        try check(!drawing.isColorRotationEnabled, "Automatic color rotation must be off by default")
        for _ in 0..<3 {
            drawing.draw(at: .zero, start: .zero, on: 1)
            drawing.finishStroke()
        }
        try check(drawing.strokes.map(\.colorIndex) == [0, 0, 0], "Default strokes did not stay red")
        drawing.selectColor(4)
        for _ in 0..<3 {
            drawing.draw(at: .zero, start: .zero, on: 1)
            drawing.finishStroke()
        }
        try check(drawing.strokes.suffix(3).map(\.colorIndex) == [4, 4, 4], "Selected blue did not stay fixed")
        drawing.selectColor(-1)
        drawing.selectColor(DrawingState.palette.count)
        try check(drawing.nextColorIndex == 4, "An invalid palette selection changed the color")
        drawing.clear()
        try check(drawing.nextColorIndex == 4 && !drawing.isColorRotationEnabled,
                  "Clearing strokes changed fixed-color settings")
    }

    @MainActor
    static func colorRotation() throws {
        let drawing = DrawingState()
        drawing.isColorRotationEnabled = true
        for index in 0..<8 {
            drawing.draw(at: CGPoint(x: 10, y: 20), start: .zero, on: 1)
            drawing.draw(at: CGPoint(x: 30, y: 40), start: .zero, on: 1)
            try check(drawing.currentStroke?.colorIndex == index % 6, "Color changed during a stroke")
            try check(drawing.nextColorIndex == index % 6, "Palette advanced before mouse up")
            drawing.finishStroke()
            try check(drawing.nextColorIndex == (index + 1) % 6, "Palette did not advance on mouse up")
        }
        try check(drawing.strokes.map(\.colorIndex) == [0, 1, 2, 3, 4, 5, 0, 1], "Six-color wrap failed")
        try check(drawing.strokes.first?.points == [.zero, CGPoint(x: 10, y: 20), CGPoint(x: 30, y: 40)],
                  "Stroke lost mouse points")
        drawing.finishStroke()
        try check(drawing.strokes.count == 8, "Empty mouse up added a stroke")
    }

    @MainActor
    static func toggleDuringStroke() throws {
        let drawing = DrawingState()
        drawing.selectColor(2)
        drawing.draw(at: .zero, start: .zero, on: 1)
        drawing.isColorRotationEnabled = true
        try check(drawing.currentStroke?.colorIndex == 2, "Enabling rotation recolored the current stroke")
        drawing.finishStroke()
        try check(drawing.nextColorIndex == 3, "Enabled rotation did not advance after mouse up")
        drawing.draw(at: .zero, start: .zero, on: 1)
        drawing.isColorRotationEnabled = false
        drawing.finishStroke()
        drawing.draw(at: .zero, start: .zero, on: 1)
        drawing.finishStroke()
        try check(drawing.strokes.map(\.colorIndex) == [2, 3, 3], "Disabling rotation did not keep the current color")
        drawing.isColorRotationEnabled = true
        try check(!DrawingState().isColorRotationEnabled, "A new app state did not default to rotation off")
    }

    @MainActor
    static func undoAcrossDisplays() throws {
        let drawing = DrawingState()
        for display: CGDirectDisplayID in [1, 2, 1] {
            drawing.draw(at: .zero, start: .zero, on: display)
            drawing.finishStroke()
        }
        drawing.undo()
        try check(drawing.strokes.map(\.displayID) == [1, 2], "Undo removed the wrong display's stroke")
        drawing.undo()
        try check(drawing.strokes.map(\.displayID) == [1], "Undo did not use global drawing order")
        drawing.undo()
        drawing.undo()
        try check(drawing.strokes.isEmpty, "Undo on an empty canvas failed")
    }

    @MainActor
    static func clearWhileDrawing() throws {
        let drawing = DrawingState()
        drawing.selectColor(4)
        drawing.isColorRotationEnabled = true
        drawing.draw(at: .zero, start: .zero, on: 1)
        drawing.finishStroke()
        drawing.draw(at: CGPoint(x: 1, y: 1), start: .zero, on: 1)
        drawing.clear()
        try check(drawing.strokes.isEmpty && drawing.currentStroke == nil, "Clear left a stroke behind")
        try check(drawing.nextColorIndex == 5 && drawing.isColorRotationEnabled,
                  "Clear did not preserve the selected color and rotation setting")
        drawing.finishStroke()
        try check(drawing.strokes.isEmpty, "A cleared stroke was committed")
    }

    @MainActor
    static func cancelledGestureDoesNotReturn() throws {
        let drawing = DrawingState()
        for cancel in [drawing.clear, drawing.undo] {
            drawing.draw(at: CGPoint(x: 10, y: 10), start: .zero, on: 1)
            cancel()
            // The same held mouse must not start a new stroke after Clear or Undo.
            drawing.draw(at: CGPoint(x: 20, y: 20), start: .zero, on: 1, beginsStroke: false)
            drawing.finishStroke()
            try check(drawing.strokes.isEmpty, "Cancelled stroke returned on mouse movement or release")
        }
        drawing.draw(at: CGPoint(x: 30, y: 30), start: .zero, on: 1)
        drawing.finishStroke()
        try check(drawing.strokes.count == 1 && drawing.strokes.first?.colorIndex == 0,
                  "The next mouse press did not start a fresh red stroke")
    }

    @MainActor
    static func singleClick() throws {
        let drawing = DrawingState()
        let point = CGPoint(x: 100, y: 200)
        drawing.draw(at: point, start: point, on: 1)
        drawing.draw(at: .zero, start: .zero, on: 2)
        drawing.finishStroke()
        try check(drawing.strokes.first?.points == [point], "Single-click dot was lost or duplicated")
        try check(drawing.strokes.first?.displayID == 1, "An active stroke crossed displays")
    }

    @MainActor
    static func transparentBackground() throws {
        let drawing = DrawingState()
        drawing.draw(at: CGPoint(x: 300, y: 200), start: CGPoint(x: 100, y: 200), on: 1)
        drawing.finishStroke()
        let renderer = ImageRenderer(content: ContentView(
            drawing: drawing, displayID: 1, onExit: {}
        ).frame(width: 800, height: 600))
        renderer.scale = 1
        renderer.isOpaque = false
        guard let image = renderer.cgImage else { throw Failure(message: "Canvas rendering failed") }
        let bitmap = NSBitmapImageRep(cgImage: image)
        try check(bitmap.colorAt(x: 10, y: 500)?.alphaComponent == 0,
                  "Empty canvas blocks the live screen")
        try check((bitmap.colorAt(x: 180, y: 200)?.alphaComponent ?? 0) > 0.9,
                  "Rendered image is missing the stroke")
        try check((bitmap.colorAt(x: 400, y: 50)?.alphaComponent ?? 0) > 0.5,
                  "Rendered image is missing the toolbar")
    }
}
