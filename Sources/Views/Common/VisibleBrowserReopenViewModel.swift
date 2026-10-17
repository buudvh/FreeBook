import Combine
import UIKit

/// Trạng thái kéo/thả, dán mép và bung/thu của widget trình duyệt thu nhỏ (dựng lại ở 1.3.533 sau khi tách
/// khỏi hub nổi).
///
/// **Giữ nguyên hai key UserDefaults cũ** (`visibleBrowserReopenVerticalRatio`, `visibleBrowserReopenEdge`) nên
/// vị trí người dùng đã chọn trước khi widget gộp vào hub (1.3.524) vẫn còn.
///
/// **Cố ý là lớp riêng**, không tái dùng `FloatingHubViewModel` hay `FloatingWidgetViewModel` của TTS: mỗi lớp
/// đó hard-code key vị trí của nó, dùng chung là hai widget **ghi đè vị trí của nhau**. Phần hình học vẫn
/// dùng chung `FloatingWidgetGeometry`.
@MainActor
final class VisibleBrowserReopenViewModel: ObservableObject {
    @Published var verticalRatio: CGFloat
    @Published var edgeDirection: EdgeDirection
    @Published var mode: WidgetMode
    @Published var isDragging = false

    /// Tự thu về `.peeking` sau 3 giây — cùng nhịp với hub và widget TTS.
    static let autoHideNanoseconds: UInt64 = 3_000_000_000

    static let storedRatioKey = "visibleBrowserReopenVerticalRatio"
    static let storedEdgeKey = "visibleBrowserReopenEdge"
    /// Mặc định 1,0 = sát đáy màn (kẹp theo vùng an toàn), giữ đúng hành vi của widget cũ.
    private static let defaultRatio: CGFloat = 1.0

    private var autoHideTask: Task<Void, Never>?

    init() {
        let defaults = UserDefaults.standard
        let storedRatio = defaults.double(forKey: Self.storedRatioKey)
        let storedEdge = defaults.string(forKey: Self.storedEdgeKey)
        self.verticalRatio = storedRatio > 0 ? CGFloat(storedRatio) : Self.defaultRatio
        self.edgeDirection = (storedEdge == "left") ? .left : .right
        self.mode = .peeking
    }

    func reveal() {
        autoHideTask?.cancel()
        mode = .revealed
        startAutoHideTimer()
    }

    func hide() {
        autoHideTask?.cancel()
        mode = .peeking
    }

    /// Đưa widget về trạng thái xuất hiện chuẩn (nép mép, không kéo dở). Gọi mỗi lần widget hiện lại.
    func prepareForAppearance() {
        isDragging = false
        hide()
    }

    func handleDragStart() {
        autoHideTask?.cancel()
        isDragging = true
    }

    /// Chốt vị trí sau khi nhả tay: snap về cạnh gần nhất, kẹp Y trong vùng hợp lệ, quyết định bung hay thu,
    /// rồi lưu tỉ lệ/cạnh để không reset khi view dựng lại.
    func handleDragEnd(
        finalPosition: CGPoint,
        widgetSize: CGFloat,
        screenWidth: CGFloat,
        screenHeight: CGFloat,
        topMargin: CGFloat,
        bottomMargin: CGFloat,
        edgeSnapDistance: CGFloat
    ) {
        autoHideTask?.cancel()
        guard screenWidth > 0, screenHeight > 0 else {
            isDragging = false
            return
        }

        let targetEdge = FloatingWidgetGeometry.nearestEdge(
            centerX: finalPosition.x,
            screenWidth: screenWidth
        )
        let targetY = FloatingWidgetGeometry.clampedCenterY(
            finalPosition.y,
            widgetHeight: widgetSize,
            screenHeight: screenHeight,
            topMargin: topMargin,
            bottomMargin: bottomMargin
        )

        verticalRatio = targetY / screenHeight
        edgeDirection = targetEdge

        // Thả sát mép thì thu, thả giữa màn thì giữ bung — cùng ngưỡng với hub.
        let edgeDistance = min(finalPosition.x, screenWidth - finalPosition.x)
        mode = edgeDistance <= edgeSnapDistance ? .peeking : .revealed
        isDragging = false

        UserDefaults.standard.set(Double(verticalRatio), forKey: Self.storedRatioKey)
        UserDefaults.standard.set(targetEdge == .left ? "left" : "right", forKey: Self.storedEdgeKey)

        if mode == .revealed {
            startAutoHideTimer()
        }
    }

    func startAutoHideTimer() {
        autoHideTask?.cancel()
        guard !isDragging else { return }
        autoHideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: Self.autoHideNanoseconds)
            guard !Task.isCancelled else { return }
            guard mode == .revealed, !isDragging else { return }
            mode = .peeking
        }
    }
}
