import Combine
import SwiftUI

/// Trạng thái kéo/thả, dán mép và bung/thu của widget trình duyệt thu nhỏ.
///
/// Cùng vai trò với `FloatingWidgetViewModel` của widget TTS và `NotificationFloatingWidgetViewModel` của
/// widget thông báo, và **giữ nguyên hai key UserDefaults cũ** (`visibleBrowserReopenVerticalRatio`,
/// `visibleBrowserReopenEdge`) nên vị trí người dùng đã chọn trước đây không mất khi hình khối đổi từ pill
/// sang nút tròn (1.3.476).
///
/// **Cố ý không tái dùng `NotificationFloatingWidgetViewModel`**: lớp đó hard-code key
/// `notificationWidgetVerticalRatio`, nên hai widget dùng chung sẽ ghi đè vị trí của nhau. Repo đã chấp
/// nhận khuôn "mỗi widget một ViewModel giữ key riêng"; phần hình học vẫn dùng chung
/// `FloatingWidgetGeometry`.
@MainActor
final class VisibleBrowserReopenViewModel: ObservableObject {
    @Published var verticalRatio: CGFloat
    @Published var edgeDirection: EdgeDirection
    @Published var mode: WidgetMode
    @Published var isDragging = false
    @Published var disableAutoHide: Bool = false {
        didSet {
            if disableAutoHide {
                autoHideTask?.cancel()
            }
        }
    }

    /// Tự thu về `.peeking` sau 3 giây — cùng nhịp với hai widget nổi kia.
    static let autoHideNanoseconds: UInt64 = 3_000_000_000

    private var autoHideTask: Task<Void, Never>?
    private let storedRatioKey = "visibleBrowserReopenVerticalRatio"
    private let storedEdgeKey = "visibleBrowserReopenEdge"

    init() {
        let storedRatio = UserDefaults.standard.double(forKey: storedRatioKey)
        let storedEdge = UserDefaults.standard.string(forKey: storedEdgeKey)
        // Mặc định 1.0 = sát đáy màn, giữ nguyên hành vi cũ của widget này.
        self.verticalRatio = storedRatio > 0 ? CGFloat(storedRatio) : 1.0
        self.edgeDirection = (storedEdge == "left") ? .left : .right
        self.mode = .peeking
    }

    func reveal() {
        autoHideTask?.cancel()
        mode = .revealed
        if !disableAutoHide {
            startAutoHideTimer()
        }
    }

    func hide() {
        autoHideTask?.cancel()
        mode = .peeking
    }

    func toggle() {
        mode == .revealed ? hide() : reveal()
    }

    func handleDragStart() {
        autoHideTask?.cancel()
        isDragging = true
    }

    /// Chốt vị trí sau khi nhả tay: snap về cạnh gần nhất, kẹp Y trong vùng hợp lệ, quyết định bung hay thu,
    /// rồi lưu tỉ lệ/cạnh để không reset khi view dựng lại.
    ///
    /// Khác bản pill cũ: nút tròn có **một** cỡ duy nhất nên chỉ nhận `widgetSize`, và thêm quyết định
    /// `.peeking`/`.revealed` theo khoảng cách tới mép — cùng công thức `NotificationFloatingWidgetViewModel`.
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

        // Thả sát mép thì thu, thả giữa màn thì giữ bung.
        let edgeDistance = min(finalPosition.x, screenWidth - finalPosition.x)
        mode = edgeDistance <= edgeSnapDistance ? .peeking : .revealed
        isDragging = false

        UserDefaults.standard.set(Double(verticalRatio), forKey: storedRatioKey)
        UserDefaults.standard.set(targetEdge == .left ? "left" : "right", forKey: storedEdgeKey)

        if mode == .revealed && !disableAutoHide {
            startAutoHideTimer()
        }
    }

    func startAutoHideTimer() {
        autoHideTask?.cancel()
        guard !isDragging, !disableAutoHide else { return }
        autoHideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: Self.autoHideNanoseconds)
            guard !Task.isCancelled else { return }
            guard mode == .revealed, !isDragging, !disableAutoHide else { return }
            mode = .peeking
        }
    }

    func cancelTasks() {
        autoHideTask?.cancel()
    }
}
