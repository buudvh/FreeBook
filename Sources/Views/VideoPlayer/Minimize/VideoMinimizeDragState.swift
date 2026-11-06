import CoreGraphics
import Observation

/// Trạng thái **co khung phim** khi thu nhỏ trình phát (1.3.751): vuốt xuống khung phim ở màn dọc, nút ⌄, nút "Cửa sổ
/// nhỏ". `VideoPlayerController` giữ một bản cho mỗi màn; `VideoMinimizeDragContainer` đọc để co / dời khung phim và làm
/// mờ phần còn lại của màn (lộ màn phía sau).
///
/// - Đang kéo: `progress = offset / dragRange`, đích = chỗ đậu của cửa sổ nhỏ (`VideoMiniPlayerWindowManager.dockFrame`)
///   với **mọi** kiểu thu nhỏ — khung phim co và trôi về mép theo tay.
/// - `commit(to:fadesOut:)` (gọi trong `withAnimation`): `progress = 1` tới đích cuối — khung cửa sổ nhỏ, hoặc nút hub và
///   mờ dần (`fadesOut`).
/// - Đích là toạ độ **màn hình** (toàn cục); container tự đổi về toạ độ của nó.
/// Chỉ dùng trên main (màn, controller); không gắn `@MainActor` để controller tạo được ở giá trị mặc định của thuộc tính.
@Observable
final class VideoMinimizeDragState {
    /// Kéo được chừng này (pt) thì khung phim tới hẳn đích.
    static let dragRange: CGFloat = 420

    private(set) var offset: CGFloat = 0
    private(set) var target: CGRect?
    private(set) var isCommitted = false
    private(set) var fadesOut = false

    var progress: CGFloat {
        isCommitted ? 1 : min(1, max(0, offset) / Self.dragRange)
    }

    /// Bắt đầu kéo: chốt đích trung gian (chỗ đậu cửa sổ nhỏ).
    func begin(target newTarget: CGRect) {
        target = newTarget
        offset = 0
        isCommitted = false
        fadesOut = false
    }

    func update(offset newOffset: CGFloat) {
        guard !isCommitted else { return }
        offset = max(0, newOffset)
    }

    /// Nhả tay chưa tới ngưỡng ⇒ về như cũ (gọi trong `withAnimation`).
    func cancel() {
        offset = 0
        isCommitted = false
        fadesOut = false
    }

    func commit(to newTarget: CGRect, fadesOut fades: Bool) {
        target = newTarget
        fadesOut = fades
        isCommitted = true
    }
}
