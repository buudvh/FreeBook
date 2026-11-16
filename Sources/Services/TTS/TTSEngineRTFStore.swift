import Foundation

/// **RTF** (real-time factor) của đoạn vừa tổng hợp — `rtf = (synthesisMs / 1_000) / speechSeconds`.
///
/// 0,32 nghĩa là tổng hợp mất 32% thời lượng lời đọc (nhanh ~3× thời gian thực); > 1 nghĩa là chậm hơn thời gian thực.
///
/// Mẫu số là thời lượng **lời đọc**, không tính khoảng lặng engine tự chèn (khoảng nghỉ giữa các chunk + khoảng lặng
/// đuôi theo ranh giới) — 1.3.958, anh Bửu duyệt "Đổi, bỏ khoảng lặng". Khoảng lặng không tốn công tổng hợp nên chia
/// cho cả nó làm đoạn ngắn trông nhanh hơn thật (đoạn 0,9 s lời + 0,2 s lặng: 0,45 thay vì 0,56). Công thức nằm **một
/// chỗ** ở `record(text:synthesisMs:speechSeconds:)` để ba engine không lệch nhau.
///
/// Khoá theo **chữ đã nói** (sau khi áp quy tắc thay thế) — cùng khoá với `VieNeuEngineBadgeStore` để sheet điều
/// khiển nhanh tra ra badge đúng đoạn đang phát. Ghi từ cả hai engine offline: **VieNeu** (Nano/Turbo) và
/// **Piper / NghiTTS**.
///
/// Số đo lấy trong engine (chỉ gồm suy luận), **không** lẫn thời gian chờ hàng đợi — cùng quy ước với
/// `VieNeuTTSService` (chú thích "synthesisMs của engine đo bên trong").
final class TTSEngineRTFStore: @unchecked Sendable {
    static let shared = TTSEngineRTFStore()

    private let lock = NSLock()
    private var values: [String: Double] = [:]
    private var order: [String] = []
    private let capacity = 64

    private init() {}

    /// Lời đọc ngắn hơn mức này (đoạn im lặng, đoạn chỉ có dấu câu) thì không ghi: chia cho gần 0 ra số vô nghĩa.
    private static let minimumSpeechSeconds = 0.05

    /// `speechSeconds` = thời lượng audio **trừ** khoảng lặng engine chèn thêm.
    func record(text: String, synthesisMs: Double, speechSeconds: Double) {
        guard speechSeconds >= Self.minimumSpeechSeconds else { return }
        let rtf = synthesisMs / 1_000 / speechSeconds
        let key = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, rtf.isFinite, rtf > 0 else { return }
        lock.lock()
        defer { lock.unlock() }
        if values[key] == nil { order.append(key) }
        values[key] = rtf
        if order.count > capacity {
            values[order.removeFirst()] = nil
        }
    }

    /// RTF của đoạn có chữ này; `nil` khi chưa tổng hợp (hoặc đoạn nói trước khi có badge).
    func rtf(for text: String) -> Double? {
        let key = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }
        lock.lock()
        defer { lock.unlock() }
        return values[key]
    }
}
