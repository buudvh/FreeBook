import Foundation

/// Nhãn **"model · tăng tốc"** của từng đoạn VieNeu vừa tổng hợp (1.3.942, anh Bửu duyệt mockup) — cho badge ở sheet điều
/// khiển nhanh TTS (`TTSEngineBadge`): "Turbo · AMX", "Nano · Core ML" khi đang tăng tốc; "Turbo · CPU" / "Nano · CPU"
/// khi AMX tự tắt hoặc Core ML chưa sẵn / lùi ORT.
///
/// - Ghi: engine Nano (`VieNeuTTSService`) và Turbo (`VieNeuTurboTTSService`) sau mỗi lượt tổng hợp thành công; đọc lai
///   Nano · Turbo đi qua chính hai engine này nên tự có nhãn đúng model của từng đoạn.
/// - Khoá: chữ đoạn **engine nhận** (đã áp từ điển thay thế `TTSReplacementManager`), bỏ khoảng trắng hai đầu. Bên đọc
///   (`TTSQuickControlNowReading`) áp cùng phép thay thế rồi tra.
/// - Giữ 64 đoạn gần nhất (đủ cho cửa sổ nạp trước); câu trùng chữ lấy nhãn mới nhất.
/// Chỉ một lần tra từ điển mỗi khi câu đang phát đổi lúc sheet mở — không theo dõi gì thêm, không tốn hiệu năng đọc.
final class VieNeuEngineBadgeStore: @unchecked Sendable {
    struct Label: Equatable, Sendable {
        let model: VieNeuModelChoice
        let accelerated: Bool

        var title: String {
            let modelName = model == .turbo ? "Turbo" : "Nano"
            let acceleration = accelerated ? (model == .turbo ? "AMX" : "Core ML") : "CPU"
            return "\(modelName) · \(acceleration)"
        }
    }

    static let shared = VieNeuEngineBadgeStore()

    private let lock = NSLock()
    private var labels: [String: Label] = [:]
    private var order: [String] = []
    private let capacity = 64

    func record(text: String, model: VieNeuModelChoice, accelerated: Bool) {
        let key = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        if labels[key] == nil { order.append(key) }
        labels[key] = Label(model: model, accelerated: accelerated)
        if order.count > capacity {
            labels[order.removeFirst()] = nil
        }
    }

    func label(for text: String) -> Label? {
        let key = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }
        lock.lock()
        defer { lock.unlock() }
        return labels[key]
    }
}
