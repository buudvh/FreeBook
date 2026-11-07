import Foundation

/// Kênh **lệnh chuyển tab** gửi tới `MainTabView` — từ màn không nằm trong cây tab (màn xem phim trình bày bằng UIKit)
/// và từ nút Home nổi của trang con. Thay cho notification tên chuỗi: thêm lệnh mới = thêm `case`.
///
/// Một người nghe (`MainTabView`, `.task`). Mỗi lần gọi `events()` tạo stream **mới** và đóng stream cũ — task nghe bị
/// dựng lại (view tạo lại) vẫn nhận lệnh, không vướng stream đã kết thúc. Lệnh gửi lúc chưa ai nghe thì bỏ (không xếp
/// hàng): lệnh chuyển tab chỉ có nghĩa ngay lúc bấm.
@MainActor
final class MainTabNavigationEvents {
    enum Event: Equatable {
        /// Sang tab Khám phá và về **trang gốc** (bỏ mọi trang đang đẩy trong tab đó) — nút Home của màn xem phim.
        case showDiscoveryRoot
        /// Về **trang gốc** của tab đang chọn (bỏ mọi trang đang đẩy trong tab đó) — nút Home nổi của trang con
        /// (`FloatingHomePlacement`), hoặc `FloatingHomeActionProviding` của trang trình bày bằng UIKit sau khi tự đóng.
        case showCurrentTabRoot
    }

    static let shared = MainTabNavigationEvents()

    private var continuation: AsyncStream<Event>.Continuation?

    private init() {}

    func events() -> AsyncStream<Event> {
        continuation?.finish()
        let (stream, continuation) = AsyncStream<Event>.makeStream(bufferingPolicy: .bufferingNewest(1))
        self.continuation = continuation
        return stream
    }

    func send(_ event: Event) {
        guard let continuation else {
            AppLogger.shared.log("❌ [MainTabNavigation] Chưa có ai nghe lệnh chuyển tab (\(event))")
            return
        }
        continuation.yield(event)
    }
}
