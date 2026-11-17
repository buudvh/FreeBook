import Foundation

/// Đo **main thread bị kẹt** (1.3.965) — chẩn đoán "mục lục Reader giật khi đang tải truyện": log thường không có dấu vết
/// nào của lúc giao diện khựng, nên trước đây không phân biệt được nghi vấn nào đúng.
///
/// - Chỉ chạy khi công tắc **Ghi log hệ thống** bật (`AppLogger.isLoggingEnabled`; `AppLogger.init` tắt nó mỗi lần mở
///   app) — bật / tắt công tắc là bộ đo chạy / dừng theo (`UserDefaults.didChangeNotification`).
/// - Cách đo: một hàng đợi nền mỗi 0,25 s gửi một khối rỗng vào main (`DispatchQueue.main.async`) và đo bao lâu main mới
///   chạy tới nó. Khối trước chưa về thì không gửi thêm (main đang kẹt — độ trễ được đo khi khối đó về). Tốn 4 lần đánh
///   thức main mỗi giây, chỉ lúc đang bật log.
/// - Ghi log (`🐢 [MainHang]`): mỗi lần kẹt ≥ 500 ms ghi ngay một dòng; các lần ≥ 150 ms gộp thành một dòng tổng kết
///   mỗi 10 s. Mỗi dòng kèm bối cảnh đọc **trên main** ngay lúc khối về: số tác vụ tải / xuất đang chạy, Chế độ AI đang
///   chạy lượt, màn đang mở do view tự báo (`noteScreen`, vd mục lục Reader), mức nhiệt.
final class MainThreadHangMonitor: @unchecked Sendable {
    static let shared = MainThreadHangMonitor()

    private static let pingInterval: TimeInterval = 0.25
    private static let stallThresholdMs: Double = 150
    private static let singleLogThresholdMs: Double = 500
    private static let summaryInterval: CFAbsoluteTime = 10

    private let queue = DispatchQueue(label: "TangCongCac.MainThreadHangMonitor", qos: .utility)

    // Chỉ truy cập trên main.
    private var isWanted = false
    private var observer: NSObjectProtocol?
    /// Tên màn → số bản đang mở (hai màn Chi tiết chồng nhau vẫn đếm đúng).
    private var screens: [String: Int] = [:]

    // Chỉ truy cập trên `queue`.
    private var timer: DispatchSourceTimer?
    private var isPingInFlight = false
    private var windowStartedAt: CFAbsoluteTime = 0
    private var stallCount = 0
    private var stallTotalMs: Double = 0
    private var stallMaxMs: Double = 0
    private var lastContext = ""

    private init() {}

    /// Gọi một lần lúc khởi động app, trên main. Gọi lại không có tác dụng.
    func start() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.syncWithLoggingSwitch()
        }
        syncWithLoggingSwitch()
    }

    /// View báo màn của nó đang hiện / đã đóng — chỉ để ghi bối cảnh vào dòng log. Gọi trên main.
    func noteScreen(_ name: String, visible: Bool) {
        let count = (screens[name] ?? 0) + (visible ? 1 : -1)
        screens[name] = count > 0 ? count : nil
    }

    // MARK: - Bật / tắt theo công tắc log (main)

    private func syncWithLoggingSwitch() {
        let wanted = AppLogger.shared.isLoggingEnabled
        guard wanted != isWanted else { return }
        isWanted = wanted
        queue.async {
            if wanted {
                self.startTimer()
            } else {
                self.stopTimer()
            }
        }
    }

    // MARK: - Đo (queue)

    private func startTimer() {
        guard timer == nil else { return }
        resetWindow(at: CFAbsoluteTimeGetCurrent())
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now() + Self.pingInterval, repeating: Self.pingInterval, leeway: .milliseconds(50))
        source.setEventHandler { [weak self] in self?.ping() }
        source.resume()
        timer = source
    }

    private func stopTimer() {
        timer?.cancel()
        timer = nil
        isPingInFlight = false
    }

    private func ping() {
        guard !isPingInFlight else { return }
        isPingInFlight = true
        let sentAt = CFAbsoluteTimeGetCurrent()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let latencyMs = (CFAbsoluteTimeGetCurrent() - sentAt) * 1_000
            let context = latencyMs >= Self.stallThresholdMs ? self.mainContext() : nil
            self.queue.async { self.pong(latencyMs: latencyMs, context: context) }
        }
    }

    private func pong(latencyMs: Double, context: String?) {
        isPingInFlight = false
        let now = CFAbsoluteTimeGetCurrent()
        if latencyMs >= Self.stallThresholdMs {
            stallCount += 1
            stallTotalMs += latencyMs
            stallMaxMs = max(stallMaxMs, latencyMs)
            if let context { lastContext = context }
            if latencyMs >= Self.singleLogThresholdMs {
                AppLogger.shared.log("🐢 [MainHang] Main kẹt \(Int(latencyMs)) ms · \(context ?? lastContext)")
            }
        }
        guard now - windowStartedAt >= Self.summaryInterval else { return }
        if stallCount > 0 {
            AppLogger.shared.log(
                "🐢 [MainHang] \(Int(now - windowStartedAt)) s qua: \(stallCount) lần kẹt ≥ \(Int(Self.stallThresholdMs)) ms, "
                    + "lâu nhất \(Int(stallMaxMs)) ms, tổng \(Int(stallTotalMs)) ms · \(lastContext)"
            )
        }
        resetWindow(at: now)
    }

    private func resetWindow(at time: CFAbsoluteTime) {
        windowStartedAt = time
        stallCount = 0
        stallTotalMs = 0
        stallMaxMs = 0
    }

    // MARK: - Bối cảnh (main)

    /// Đọc trên main ngay lúc khối đo về — mọi trạng thái ở đây thuộc main.
    private func mainContext() -> String {
        var parts: [String] = []
        let running = DownloadManager.shared.tasks.filter { $0.status == .running }.count
        parts.append(running > 0 ? "tải/xuất \(running) tác vụ" : "không tải")
        let aiTurn = MainActor.assumeIsolated { GoogleAIModeSessionController.shared.isTurnActive }
        if aiTurn { parts.append("Chế độ AI đang chạy lượt") }
        if !screens.isEmpty { parts.append(screens.keys.sorted().joined(separator: ", ")) }
        parts.append("nhiệt \(Self.thermalLabel(ProcessInfo.processInfo.thermalState))")
        return parts.joined(separator: " · ")
    }

    private static func thermalLabel(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "Mát"
        case .fair: return "Ấm"
        case .serious: return "Nóng"
        case .critical: return "Rất nóng"
        @unknown default: return "?"
        }
    }
}
