import CoreGraphics
import Observation

/// Trạng thái **co khung phim** khi thu nhỏ trình phát (1.3.751): vuốt xuống khung phim ở màn dọc, nút ⌄, nút "Cửa sổ
/// nhỏ". `VideoPlayerController` giữ một bản cho mỗi màn; `VideoMinimizeDragContainer` đọc để co / dời khung phim và làm
/// mờ phần còn lại của màn (lộ màn phía sau).
///
/// - Đang kéo: `progress = offset / travel`, đích = chỗ đậu của cửa sổ nhỏ (`VideoMiniPlayerWindowManager.dockFrame`,
///   góc dưới phải) với **mọi** kiểu thu nhỏ. `travel` = quãng dọc từ mép trên khung phim tới mép trên chỗ đậu ⇒ mép trên
///   khung phim đi **đúng theo ngón tay** (kiểu YouTube, 1.3.765), khung co dần và dịch về mép phải.
/// - `commit(to:fadesOut:)` (gọi trong `withAnimation`): `progress = 1` tới đích cuối — khung cửa sổ nhỏ, hoặc nút hub và
///   mờ dần (`fadesOut`).
/// - Đích là toạ độ **màn hình** (toàn cục); container tự đổi về toạ độ của nó.
/// Chỉ dùng trên main (màn, controller); không gắn `@MainActor` để controller tạo được ở giá trị mặc định của thuộc tính.
@Observable
final class VideoMinimizeDragState {
    /// Quãng kéo khi chưa biết đích (không xảy ra khi kéo thật).
    static let fallbackTravel: CGFloat = 420

    private(set) var offset: CGFloat = 0
    private(set) var target: CGRect?
    private(set) var isCommitted = false
    private(set) var fadesOut = false
    /// Kéo được chừng này (pt) thì khung phim tới hẳn đích.
    private(set) var travel: CGFloat = VideoMinimizeDragState.fallbackTravel

    var progress: CGFloat {
        isCommitted ? 1 : min(1, max(0, offset) / max(1, travel))
    }

    /// Bắt đầu kéo: chốt đích trung gian (chỗ đậu cửa sổ nhỏ) và quãng dọc tới đó.
    func begin(target newTarget: CGRect, travel newTravel: CGFloat) {
        target = newTarget
        travel = newTravel > 40 ? newTravel : Self.fallbackTravel
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
