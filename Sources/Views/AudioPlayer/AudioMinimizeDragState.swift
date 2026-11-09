import SwiftUI
import Observation

/// Vuốt xuống để **thu nhỏ** màn nghe (đóng màn, nhạc vẫn phát): cả màn trôi theo tay (`AudioMinimizeDragContainer` đọc
/// `offset`), nhả tay quá ngưỡng ⇒ màn trượt nốt xuống rồi đóng; chưa tới ⇒ bật về chỗ cũ.
///
/// Hướng chốt ở nhịp kéo đầu tiên: chỉ nhận kéo **xuống** là chính (dọc ≥ 1,2 lần ngang) — kéo ngang để sang trang, kéo
/// lên… bị bỏ cho tới khi nhấc tay. Chỉ `AudioMinimizeDragContainer` đọc `offset` nên mỗi nhịp kéo chỉ vẽ lại container.
@MainActor
@Observable
final class AudioMinimizeDragState {
    /// Độ lệch dọc hiện tại của màn (≥ 0).
    private(set) var offset: CGFloat = 0

    @ObservationIgnored private var isTracking = false
    @ObservationIgnored private var isRejected = false

    /// Kéo quá chừng này (pt) hoặc vuốt nhanh (đích dự đoán quá `flickDistance`) ⇒ thu nhỏ.
    private static let commitDistance: CGFloat = 140
    private static let flickDistance: CGFloat = 420

    func update(translation: CGSize) {
        if !isTracking, !isRejected {
            guard translation.height > 0, translation.height >= abs(translation.width) * 1.2 else {
                isRejected = true
                return
            }
            isTracking = true
        }
        guard isTracking else { return }
        offset = max(0, translation.height)
    }

    /// Nhả tay. `true` ⇒ màn phải thu nhỏ (gọi `slideOut()` rồi đóng); `false` ⇒ đã bật về chỗ cũ.
    func end(translation: CGSize, predictedEndTranslation: CGSize) -> Bool {
        defer {
            isTracking = false
            isRejected = false
        }
        guard isTracking else { return false }
        if translation.height > Self.commitDistance || predictedEndTranslation.height > Self.flickDistance {
            return true
        }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
            offset = 0
        }
        return false
    }

    /// Cử chỉ bị huỷ giữa chừng (không có `onEnded`) ⇒ bật về chỗ cũ nếu còn lệch.
    func cancel() {
        let wasTracking = isTracking
        isTracking = false
        isRejected = false
        guard wasTracking, offset != 0 else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
            offset = 0
        }
    }

    /// Trượt nốt màn xuống khỏi màn hình (`duration` giây) — gọi trước khi đóng màn không animation.
    func slideOut(duration: Double) {
        withAnimation(.easeOut(duration: duration)) {
            offset = max(offset + 700, 1200)
        }
    }
}
