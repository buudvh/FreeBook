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

    /// Expands the widget while the user is pulling it away from the edge.
    /// The auto-hide timer is restarted only after the drag has completed.
    public func expandForDrag() {
        autoHideTask?.cancel()
        mode = .revealed
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

    public func handleDragEnd(
        finalPosition: CGPoint,
        widgetWidth: CGFloat,
        widgetHeight: CGFloat,
        screenWidth: CGFloat,
        screenHeight: CGFloat,
        edgeSnapDistance: CGFloat
    ) {
        autoHideTask?.cancel()
        guard screenHeight > 0 else { return }
        _ = widgetWidth

        let targetEdge: EdgeDirection = finalPosition.x < screenWidth - finalPosition.x ? .left : .right
        let minY: CGFloat = widgetHeight / 2 + 92
        let maxY: CGFloat = max(minY, screenHeight - widgetHeight / 2 - 92)
        let targetY = min(max(finalPosition.y, minY), maxY)

        verticalRatio = targetY / screenHeight
        edgeDirection = targetEdge
        let edgeDistance = min(finalPosition.x, screenWidth - finalPosition.x)
        mode = edgeDistance <= edgeSnapDistance ? .peeking : .revealed
        isDragging = false

        UserDefaults.standard.set(Double(verticalRatio), forKey: storedRatioKey)
        UserDefaults.standard.set(targetEdge == .left ? "left" : "right", forKey: storedEdgeKey)
        if mode == .revealed {
            startAutoHideTimer()
        }
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
