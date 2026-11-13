import SwiftUI

// Keep the property wrapper explicit when newer SDKs also expose a State macro.
private typealias ViewState<Value> = SwiftUI.State<Value>

struct Stroke {
    let displayID: CGDirectDisplayID
    let colorIndex: Int
    var points: [CGPoint]
}

@MainActor
final class DrawingState: ObservableObject {
    static let palette: [Color] = [.red, .orange, .yellow, .green, .blue, .purple]
    static let colorNames = ["빨강", "주황", "노랑", "초록", "파랑", "보라"]
    static let lineWidth: CGFloat = 5

    @Published private(set) var strokes: [Stroke] = []
    @Published private(set) var currentStroke: Stroke?
    @Published private(set) var nextColorIndex = 0
    @Published var isColorRotationEnabled = false

    func selectColor(_ index: Int) {
        guard Self.palette.indices.contains(index) else { return }
        nextColorIndex = index
    }

    func draw(at point: CGPoint, start: CGPoint, on displayID: CGDirectDisplayID,
              beginsStroke: Bool = true) {
        if currentStroke == nil {
            guard beginsStroke else { return }
            currentStroke = Stroke(displayID: displayID, colorIndex: nextColorIndex, points: [start])
        }
        guard currentStroke?.displayID == displayID else { return }
        if currentStroke?.points.last != point { currentStroke?.points.append(point) }
    }

    func finishStroke() {
        guard let currentStroke else { return }
        strokes.append(currentStroke)
        self.currentStroke = nil
        if isColorRotationEnabled {
            nextColorIndex = (currentStroke.colorIndex + 1) % Self.palette.count
        }
    }

    func undo() {
        currentStroke = nil
        if !strokes.isEmpty { strokes.removeLast() }
    }

    func clear() {
        strokes.removeAll()
        currentStroke = nil
    }
}

struct ColorRotationToggle: View {
    @ObservedObject var drawing: DrawingState

    var body: some View {
        Toggle("자동 색상", isOn: $drawing.isColorRotationEnabled)
            .help("켜면 선 하나를 마칠 때마다 다음 색상으로 바뀝니다")
            .accessibilityIdentifier("colorRotationToggle")
    }
}

struct ContentView: View {
    @ObservedObject var drawing: DrawingState
    @ViewState private var isDragging = false
    let displayID: CGDirectDisplayID
    let onExit: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            Canvas { context, _ in
                for stroke in drawing.strokes where stroke.displayID == displayID {
                    render(stroke, in: &context)
                }
                if let stroke = drawing.currentStroke, stroke.displayID == displayID {
                    render(stroke, in: &context)
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { value in
                    drawing.draw(at: value.location, start: value.startLocation,
                                 on: displayID, beginsStroke: !isDragging)
                    isDragging = true
                }
                .onEnded { value in
                    drawing.draw(at: value.location, start: value.startLocation,
                                 on: displayID, beginsStroke: !isDragging)
                    isDragging = false
                    drawing.finishStroke()
                })
            .accessibilityLabel("화면 판서 영역")

            toolbar.padding(.top, 28)
        }
        .background(.clear)
        .clipped()
        .ignoresSafeArea()
    }

    private var toolbar: some View {
        HStack(spacing: 16) {
            Label("판서", systemImage: "pencil.tip")
                .fontWeight(.semibold)
            Divider().frame(height: 20)
            HStack(spacing: 5) {
                ForEach(DrawingState.palette.indices, id: \.self) { index in
                    Button { drawing.selectColor(index) } label: {
                        Circle()
                            .fill(DrawingState.palette[index])
                            .frame(width: 11, height: 11)
                            .padding(3)
                            .overlay(Circle().strokeBorder(.white,
                                lineWidth: index == drawing.nextColorIndex ? 2 : 0))
                    }
                    .help("\(DrawingState.colorNames[index])색 선택")
                    .accessibilityLabel("\(DrawingState.colorNames[index])색")
                    .accessibilityValue(index == drawing.nextColorIndex ? "선택됨" : "")
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("선 색상")
            ColorRotationToggle(drawing: drawing)
                .toggleStyle(.switch)
            Button(action: drawing.undo) { Image(systemName: "arrow.uturn.backward") }
                .help("실행 취소 (⌘Z)")
                .disabled(drawing.strokes.isEmpty && drawing.currentStroke == nil)
                .accessibilityLabel("실행 취소")
            Button(action: drawing.clear) { Image(systemName: "trash") }
                .help("모두 지우기 (Delete)")
                .accessibilityLabel("모두 지우기")
            Divider().frame(height: 20)
            Button("완료  Esc", action: onExit)
                .help("판서 종료 (Esc / Q / 전역 단축키)")
        }
        .font(.system(size: 13))
        .buttonStyle(.borderless)
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.black.opacity(0.82), in: Capsule())
        .colorScheme(.dark)
        .fixedSize()
    }

    private func render(_ stroke: Stroke, in context: inout GraphicsContext) {
        guard let first = stroke.points.first else { return }
        let color = DrawingState.palette[stroke.colorIndex]
        if stroke.points.count == 1 {
            let width = DrawingState.lineWidth
            context.fill(Path(ellipseIn: CGRect(
                x: first.x - width / 2, y: first.y - width / 2, width: width, height: width
            )), with: .color(color))
        } else {
            var path = Path()
            path.addLines(stroke.points)
            context.stroke(path, with: .color(color), style: StrokeStyle(
                lineWidth: DrawingState.lineWidth, lineCap: .round, lineJoin: .round
            ))
        }
    }
}
