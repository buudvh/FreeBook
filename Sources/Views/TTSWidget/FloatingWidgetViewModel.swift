import SwiftUI
import Combine

@MainActor
public final class FloatingWidgetViewModel: ObservableObject {
    @Published public var verticalRatio: CGFloat
    @Published public var edgeDirection: EdgeDirection
    @Published public var mode: WidgetMode
    @Published public var isDragging: Bool = false

    private var autoHideTask: Task<Void, Never>? = nil

    private let storedRatioKey = "ttsWidgetVerticalRatio"
    private let storedEdgeKey = "ttsWidgetEdge"

    public init() {
        let storedRatio = UserDefaults.standard.double(forKey: storedRatioKey)
        let storedEdge = UserDefaults.standard.string(forKey: storedEdgeKey)

        self.verticalRatio = storedRatio > 0 ? CGFloat(storedRatio) : 0.5
        self.edgeDirection = (storedEdge == "left") ? .left : .right
        self.mode = .peeking
    }

    public func reveal() {
        autoHideTask?.cancel()
        mode = .revealed
        startAutoHideTimer()
    }

    public func hide() {
        autoHideTask?.cancel()
        mode = .peeking
    }

    public func toggle() {
        mode == .revealed ? hide() : reveal()
    }

    public func handleDragStart() {
        autoHideTask?.cancel()
        isDragging = true
    }

    public func handleDragEnd(finalPosition: CGPoint, widgetSize: CGFloat, screenWidth: CGFloat, screenHeight: CGFloat) {
        autoHideTask?.cancel()
        guard screenHeight > 0 else { return }

        let targetEdge: EdgeDirection = finalPosition.x < screenWidth - finalPosition.x ? .left : .right
        let minY: CGFloat = widgetSize / 2 + 80
        let maxY: CGFloat = screenHeight - widgetSize / 2 - 100
        let targetY = min(max(finalPosition.y, minY), maxY)

        verticalRatio = targetY / screenHeight
        edgeDirection = targetEdge
        mode = .revealed
        isDragging = false

        UserDefaults.standard.set(Double(verticalRatio), forKey: storedRatioKey)
        UserDefaults.standard.set(targetEdge == .left ? "left" : "right", forKey: storedEdgeKey)
        startAutoHideTimer()
    }

    public func startAutoHideTimer() {
        autoHideTask?.cancel()
        guard !isDragging else { return }
        autoHideTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            guard mode == .revealed, !isDragging else { return }
            mode = .peeking
        }
    }

    public func cancelTasks() {
        autoHideTask?.cancel()
    }
}
