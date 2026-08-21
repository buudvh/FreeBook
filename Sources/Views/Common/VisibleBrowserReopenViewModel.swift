import SwiftUI
import Combine

@MainActor
final class VisibleBrowserReopenViewModel: ObservableObject {
    @Published var verticalRatio: CGFloat
    @Published var edgeDirection: EdgeDirection
    @Published var isDragging = false

    private let storedRatioKey = "visibleBrowserReopenVerticalRatio"
    private let storedEdgeKey = "visibleBrowserReopenEdge"

    init() {
        let storedRatio = UserDefaults.standard.double(forKey: storedRatioKey)
        let storedEdge = UserDefaults.standard.string(forKey: storedEdgeKey)
        self.verticalRatio = storedRatio > 0 ? CGFloat(storedRatio) : 1.0
        self.edgeDirection = (storedEdge == "left") ? .left : .right
    }

    func handleDragStart() {
        isDragging = true
    }

    func handleDragEnd(
        finalPosition: CGPoint,
        pillHeight: CGFloat,
        screenWidth: CGFloat,
        screenHeight: CGFloat
    ) {
        guard screenWidth > 0, screenHeight > 0 else {
            isDragging = false
            return
        }

        let targetEdge: EdgeDirection = finalPosition.x < screenWidth - finalPosition.x ? .left : .right
        let minCenterFromBottom: CGFloat = pillHeight / 2 + 8
        let maxCenterFromBottom: CGFloat = 92 - pillHeight / 2 - 6
        let centerFromBottom = min(max(screenHeight - finalPosition.y, minCenterFromBottom), maxCenterFromBottom)
        let targetY = screenHeight - centerFromBottom

        verticalRatio = targetY / screenHeight
        edgeDirection = targetEdge
        isDragging = false

        UserDefaults.standard.set(Double(verticalRatio), forKey: storedRatioKey)
        UserDefaults.standard.set(targetEdge == .left ? "left" : "right", forKey: storedEdgeKey)
    }
}
