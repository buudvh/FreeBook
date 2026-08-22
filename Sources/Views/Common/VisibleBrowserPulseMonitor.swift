import Foundation
import Combine

/// Theo dõi "trình duyệt vẫn còn sống": phát tín hiệu nháy cho widget trình duyệt khi
/// đang thu nhỏ và có ít nhất một tab đã mở ≥ `pulseThreshold` giây.
///
/// Thiết kế cố ý:
/// - **Không** timer theo từng tab, **không** polling định kỳ. Chỉ một timer one-shot
///   duy nhất, hẹn đúng khoảng thời gian còn thiếu để tab già nhất chạm ngưỡng.
/// - Mọi thay đổi trạng thái trình duyệt (thêm/xóa tab, thu nhỏ, mở lại, đóng) đều đi
///   qua `VisibleBrowserTabManager.stateDidChangeNotification` → tính lại từ tuổi thật
///   của tab, nên mở lại rồi thu nhỏ lần nữa vẫn đúng.
/// - Chỉ đổi một `@Published Bool`; hiệu ứng nháy nằm trong SwiftUI và chỉ đổi **màu**
///   (đỏ sẫm ↔ đỏ tươi, alpha luôn 1), không chạm alpha/isHidden của view container
///   nên không ảnh hưởng hit-testing.
@MainActor
final class VisibleBrowserPulseMonitor: ObservableObject {
    static let shared = VisibleBrowserPulseMonitor()

    /// Tab phải tồn tại đủ 10 giây mới được tính vào nhịp nháy.
    static let pulseThreshold: TimeInterval = 10

    @Published private(set) var isPulsing = false

    private var timer: Timer?
    private var cancellable: AnyCancellable?

    private init() {
        cancellable = NotificationCenter.default
            .publisher(for: VisibleBrowserTabManager.stateDidChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.evaluate()
            }
        evaluate()
    }

    /// Tính lại trạng thái nháy từ tuổi thật của các tab đang mở.
    func evaluate() {
        timer?.invalidate()
        timer = nil

        let manager = VisibleBrowserTabManager.shared
        guard manager.isHidden, !manager.tabs.isEmpty else {
            // Đang mở toàn màn hình, hoặc không còn tab nào: dừng nháy, dừng timer.
            setPulsing(false)
            return
        }

        let now = Date()
        let oldestAge = manager.tabs
            .map { now.timeIntervalSince($0.createdAt) }
            .max() ?? 0

        if oldestAge >= Self.pulseThreshold {
            setPulsing(true)
            return
        }

        setPulsing(false)
        let remaining = max(0.2, Self.pulseThreshold - oldestAge)
        timer = Timer.scheduledTimer(withTimeInterval: remaining, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.evaluate()
            }
        }
    }

    private func setPulsing(_ newValue: Bool) {
        guard isPulsing != newValue else { return }
        isPulsing = newValue
    }
}
