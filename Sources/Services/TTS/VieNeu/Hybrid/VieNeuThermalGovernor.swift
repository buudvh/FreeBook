import Foundation

/// Phương án B của đọc lai (1.3.934): máy **nóng** chưa — có độ trễ chống lật qua lại. Báo cáo
/// `Docs/Reports/2026-11-14-vieneu-nano-turbo-theo-ngon-ngu.md` §8.
///
/// ## Ngoại lệ luật nhiệt (anh Bửu duyệt 2026-11-14, `rules.md` mục "Thermal State Invariants")
/// `ProcessInfo.thermalState` được dùng **chỉ** để chọn model VieNeu (Nano / Turbo) cho lượt tổng hợp kế tiếp. Nó **không**
/// huỷ, điều tiết hay thu hẹp refill / prefetch / audio chương kế — luật đó giữ nguyên.
///
/// ## Ngưỡng (giá trị khởi điểm, chưa đo máy dài)
/// - Vào "nóng": mức ≥ `serious` giữ liên tục ≥ 60 s, hoặc `critical` ⇒ ngay.
/// - Ra "nóng": đã nóng ≥ 10 phút **và** `nominal` giữ liên tục ≥ 3 phút. Không ra ở `fair`: Turbo từ mát lên `fair` chỉ
///   trong vài phút (log 16 / 18) ⇒ ra ở `fair` là gần như chắc lật lại ngay.
///
/// Mức nhiệt là của **cả máy** (sạc, màn hình, app khác). Theo dõi bằng `thermalStateDidChangeNotification` (bắn ở luồng
/// bất kỳ) để mốc thời gian đúng cả lúc không có lượt tổng hợp nào hỏi; trạng thái tính lười khi có người hỏi. Một thực thể
/// cho cả app, khoá bằng `lock`.
final class VieNeuThermalGovernor: @unchecked Sendable {
    static let shared = VieNeuThermalGovernor()

    static let enterHoldSeconds: TimeInterval = 60
    static let minimumHotSeconds: TimeInterval = 600
    static let exitNominalHoldSeconds: TimeInterval = 180

    private let lock = NSLock()
    private var observer: NSObjectProtocol?
    private var state: ProcessInfo.ThermalState
    /// Lúc mức nhiệt lên `serious` trở lên (giữ nguyên khi `serious` ↔ `critical`), `nil` khi dưới `serious`.
    private var elevatedSince: TimeInterval?
    /// Lúc mức nhiệt về `nominal`, `nil` khi khác `nominal`.
    private var nominalSince: TimeInterval?
    private var hotSince: TimeInterval?

    private init() {
        let now = ProcessInfo.processInfo.systemUptime
        state = ProcessInfo.processInfo.thermalState
        elevatedSince = state.rawValue >= ProcessInfo.ThermalState.serious.rawValue ? now : nil
        nominalSince = state == .nominal ? now : nil
    }

    /// `true` khi đang ở chế độ "nóng" (đọc lai chuyển sang / giữ ở Nano). Ghi một dòng log mỗi lần đổi chế độ.
    var isHot: Bool {
        lock.lock()
        defer { lock.unlock() }
        startObservingLocked()
        record(ProcessInfo.processInfo.thermalState)
        return evaluateLocked(now: ProcessInfo.processInfo.systemUptime)
    }

    // MARK: - Nội bộ (giữ `lock`)

    private func startObservingLocked() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            self.lock.lock()
            self.record(ProcessInfo.processInfo.thermalState)
            self.lock.unlock()
        }
    }

    private func record(_ newState: ProcessInfo.ThermalState) {
        guard newState != state else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let elevated = newState.rawValue >= ProcessInfo.ThermalState.serious.rawValue
        if elevated {
            if elevatedSince == nil { elevatedSince = now }
        } else {
            elevatedSince = nil
        }
        nominalSince = newState == .nominal ? (nominalSince ?? now) : nil
        state = newState
    }

    private func evaluateLocked(now: TimeInterval) -> Bool {
        if let hotSince {
            guard now - hotSince >= Self.minimumHotSeconds,
                  state == .nominal, let nominalSince,
                  now - nominalSince >= Self.exitNominalHoldSeconds else { return true }
            self.hotSince = nil
            AppLogger.shared.log(String(
                format: "🌡️ [VieNeuHybrid] Máy đã mát (nominal %.0f s, sau %.0f phút nóng) ⇒ Turbo dùng lại được",
                now - nominalSince, (now - hotSince) / 60
            ))
            return false
        }
        guard let elevatedSince else { return false }
        let held = now - elevatedSince
        guard state == .critical || held >= Self.enterHoldSeconds else { return false }
        hotSince = now
        AppLogger.shared.log(String(
            format: "🌡️ [VieNeuHybrid] Máy nóng (%@ %.0f s) ⇒ đọc lai dùng Nano, Turbo tạm nghỉ",
            NghiSynthesisPolicy.thermalStateName(state), held
        ))
        return true
    }
}
