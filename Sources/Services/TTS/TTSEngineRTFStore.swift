import Foundation

/// **RTF** (real-time factor) của đoạn vừa tổng hợp — `rtf = (synthesisMs / 1_000) / pcmDuration`.
///
/// 0,32 nghĩa là tổng hợp mất 32% thời lượng audio (nhanh ~3× thời gian thực); > 1 nghĩa là chậm hơn thời gian thực.
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

    func record(text: String, rtf: Double) {
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
