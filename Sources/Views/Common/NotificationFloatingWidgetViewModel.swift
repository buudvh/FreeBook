import Foundation
import UIKit

/// Trạng thái kéo/thả, dán mép và bung/thu của **widget thông báo nổi**.
///
/// Cùng vai trò với `FloatingWidgetViewModel` của widget TTS và `VisibleBrowserReopenViewModel` của widget
/// trình duyệt, nhưng **cố ý là lớp riêng** chứ không tái dùng `FloatingWidgetViewModel`:
/// `FloatingWidgetViewModel` hard-code key `ttsWidgetVerticalRatio`/`ttsWidgetEdge`
/// (`FloatingWidgetViewModel.swift:20-21`), nên hai widget dùng chung lớp đó sẽ **ghi đè vị trí của nhau**
/// — kéo nút thông báo là nút nghe truyện nhảy theo. Phần hình học thì vẫn dùng chung
/// `FloatingWidgetGeometry`.
///
/// Khác một điểm về kích thước so với hai widget kia: nút thông báo có **một cỡ duy nhất** (36px, người
/// dùng chốt 2026-10-07). Vì vậy `.peeking` và `.revealed` không đổi kích thước, chỉ khác **vị trí** (ngậm
/// vào mép hay nằm trong màn) và **kiểu badge** (chấm nhỏ hay số) — hai thứ do View quyết định.
@MainActor
final class NotificationFloatingWidgetViewModel: ObservableObject {
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

    /// Tự thu về `.peeking` sau 3 giây — cùng nhịp với widget TTS, để hai widget cư xử nhất quán.
    static let autoHideNanoseconds: UInt64 = 3_000_000_000

    private var autoHideTask: Task<Void, Never>?
    private let storedRatioKey = "notificationWidgetVerticalRatio"
    private let storedEdgeKey = "notificationWidgetEdge"

    init() {
        let storedRatio = UserDefaults.standard.double(forKey: storedRatioKey)
        let storedEdge = UserDefaults.standard.string(forKey: storedEdgeKey)

        // Mặc định hơi cao hơn giữa màn (0,42) để không đè lên thanh tab ở đáy.
        self.verticalRatio = storedRatio > 0 ? CGFloat(storedRatio) : 0.42
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
    /// Khác `FloatingWidgetViewModel` ở chỗ **không** đổi kích thước theo mode, nên chỉ cần một chiều cao.
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

        // Thả sát mép thì thu, thả giữa màn thì giữ bung — cùng ngưỡng với widget TTS.
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
