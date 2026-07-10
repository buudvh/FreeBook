import SwiftUI
import Combine

@MainActor
public final class FloatingWidgetViewModel: ObservableObject {
    @Published public var verticalRatio: CGFloat
    @Published public var edgeDirection: EdgeDirection
    @Published public var mode: WidgetMode

    private var autoHideTask: Task<Void, Never>? = nil

    private let storedRatioKey = "ttsWidgetVerticalRatio"
    private let storedEdgeKey = "ttsWidgetEdge"

    public init() {
        let storedRatio = UserDefaults.standard.double(forKey: storedRatioKey)
        let storedEdge = UserDefaults.standard.string(forKey: storedEdgeKey)

        self.verticalRatio = storedRatio > 0 ? CGFloat(storedRatio) : 0.5
        self.edgeDirection = (storedEdge == "left") ? .left : .right
        self.mode = .collapsed
    }

    public func handleTapCircle(buttonSize: CGFloat, screenWidth: CGFloat) {
        autoHideTask?.cancel()
        if mode == .hidden {
            mode = .collapsed
            startAutoHideTimer(buttonSize: buttonSize, screenWidth: screenWidth)
        } else if mode == .collapsed {
            mode = .expanded
        }
    }

    public func handleOutsideTap(buttonSize: CGFloat, screenWidth: CGFloat) {
        guard mode == .expanded else { return }
        autoHideTask?.cancel()
        mode = .collapsed
        startAutoHideTimer(buttonSize: buttonSize, screenWidth: screenWidth)
    }

    public func handleDragEnd(
        finalPosition: CGPoint,
        buttonSize: CGFloat,
        screenWidth: CGFloat,
        screenHeight: CGFloat
    ) {
        autoHideTask?.cancel()
        guard screenHeight > 0 else { return }

        let targetEdge: EdgeDirection = finalPosition.x < screenWidth - finalPosition.x ? .left : .right
        let minY: CGFloat = buttonSize / 2 + 100
        let maxY: CGFloat = screenHeight - buttonSize / 2 - 120
        let targetY = min(max(finalPosition.y, minY), maxY)

        self.verticalRatio = targetY / screenHeight
        self.edgeDirection = targetEdge
        self.mode = .collapsed

        UserDefaults.standard.set(Double(self.verticalRatio), forKey: storedRatioKey)
        UserDefaults.standard.set(targetEdge == .left ? "left" : "right", forKey: storedEdgeKey)

        startAutoHideTimer(buttonSize: buttonSize, screenWidth: screenWidth)
    }

    public func startAutoHideTimer(buttonSize: CGFloat, screenWidth: CGFloat) {
        autoHideTask?.cancel()
        autoHideTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            guard mode == .collapsed else { return }

            mode = .hidden
        }
    }

    public func handleDragStart() {
        autoHideTask?.cancel()
        if mode == .hidden {
            mode = .collapsed
        }
    }

    public func cancelTasks() {
        autoHideTask?.cancel()
    }
}
