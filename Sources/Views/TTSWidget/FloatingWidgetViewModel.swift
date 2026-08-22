import SwiftUI
import Combine

@MainActor
public final class FloatingWidgetViewModel: ObservableObject {
    @Published public var verticalRatio: CGFloat
    @Published public var edgeDirection: EdgeDirection
    @Published public var mode: WidgetMode
    @Published public var isDragging: Bool = false
    @Published public var disableAutoHide: Bool = false {
        didSet {
            if disableAutoHide {
                autoHideTask?.cancel()
            }
        }
    }

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
        if !disableAutoHide {
            startAutoHideTimer()
        }
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
        guard screenWidth > 0, screenHeight > 0 else {
            isDragging = false
            return
        }
        _ = widgetWidth

        let targetEdge = FloatingWidgetGeometry.nearestEdge(
            centerX: finalPosition.x,
            screenWidth: screenWidth
        )
        let targetY = FloatingWidgetGeometry.clampedCenterY(
            finalPosition.y,
            widgetHeight: widgetHeight,
            screenHeight: screenHeight,
            topMargin: 92,
            bottomMargin: 92
        )

        verticalRatio = targetY / screenHeight
        edgeDirection = targetEdge
        let edgeDistance = min(finalPosition.x, screenWidth - finalPosition.x)
        mode = edgeDistance <= edgeSnapDistance ? .peeking : .revealed
        isDragging = false

        UserDefaults.standard.set(Double(verticalRatio), forKey: storedRatioKey)
        UserDefaults.standard.set(targetEdge == .left ? "left" : "right", forKey: storedEdgeKey)
        if mode == .revealed && !disableAutoHide {
            startAutoHideTimer()
        }
    }

    public func startAutoHideTimer() {
        autoHideTask?.cancel()
        guard !isDragging, !disableAutoHide else { return }
        autoHideTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            guard mode == .revealed, !isDragging, !disableAutoHide else { return }
            mode = .peeking
        }
    }

    public func cancelTasks() {
        autoHideTask?.cancel()
    }
}
