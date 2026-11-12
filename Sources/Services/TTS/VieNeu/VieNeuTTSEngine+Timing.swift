import Foundation

/// Đồng hồ đo **từng giai đoạn** của một chunk (1.3.878): text_encoder + duration, vòng Euler, codec.
///
/// Trước 1.3.878 `runChunk` chốt `vectorMs` **sau** `codec_decoder` ⇒ con số "vòng Euler chiếm 98%" thật ra là vòng
/// Euler **cộng** codec (đo trên PC: codec ~17% thời gian, ~20% phép tính — báo cáo
/// `Docs/Reports/2026-11-11-vieneu-nano-toi-uu.md`). Mỗi giai đoạn giờ có cả thời gian tường lẫn CPU-time
/// (`ProcessCPUClock`, cả tiến trình) — nhiệt tỉ lệ với CPU-time, không với thời gian tường.
extension VieNeuTTSEngine {
    /// Thời gian tường + CPU-time cộng dồn của **một** giai đoạn, cho cả đoạn văn (nhiều chunk).
    struct StageTime: Sendable {
        var wallMs: Double = 0
        var cpuMs: Double = 0
    }

    /// Bấm giờ nối tiếp: mỗi `lap` cộng khoảng từ mốc trước tới giờ vào một giai đoạn rồi đặt mốc mới ⇒ các giai đoạn
    /// không chồng nhau và tổng của chúng đúng bằng cả chunk.
    struct StageClock {
        private var wall = ProcessInfo.processInfo.systemUptime
        private var cpu = ProcessCPUClock.nowMs()

        init() {}

        mutating func lap(_ stage: inout StageTime) {
            let nowWall = ProcessInfo.processInfo.systemUptime
            let nowCPU = ProcessCPUClock.nowMs()
            stage.wallMs += (nowWall - wall) * 1_000
            stage.cpuMs += nowCPU - cpu
            wall = nowWall
            cpu = nowCPU
        }
    }

    /// QoS của luồng đang chạy — ghi vào log để biết lượt tổng hợp / lượt dựng session chạy ở mức nào. Luồng phụ của
    /// pool ORT được tạo lúc dựng session, nên QoS lúc dựng có thể khác QoS lúc tổng hợp.
    static func currentQoSName() -> String {
        switch DispatchQoS.QoSClass(rawValue: qos_class_self()) {
        case .userInteractive?: return "userInteractive"
        case .userInitiated?: return "userInitiated"
        case .default?: return "default"
        case .utility?: return "utility"
        case .background?: return "background"
        default: return "unspecified"
        }
    }
}
