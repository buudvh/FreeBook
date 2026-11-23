import Foundation

/// **Âm lượng theo giọng** của ba trình đọc offline — vtts, NghiTTS, VieNeu (1.3.1047, anh Bửu: "thêm config tăng âm lượng"
/// → "Làm cho cả ba", duyệt mockup https://claude.ai/artifact/SiAJyQbt7tgWohnCJesDcg). Giá trị = số dB to / nhỏ hơn mức app
/// vẫn kéo cho giọng đó (0 = như trước 1.3.1047), lưu riêng từng cặp trình đọc + giọng, kẹp `range`.
///
/// Vì sao: giọng Google Dịch (vtts) gần như chỉ có năng lượng < 1 kHz; kéo lên −14 dB (mốc `VttsLoudness`) thì rè, −17 dB thì
/// không (anh nghe thử 2026-11-23) ⇒ mặc định của giọng đó −3 dB (`defaultOffset`).
///
/// Khoá giọng (`voiceKey`): vtts = `VttsVoice.id`; NghiTTS = tên giọng (`selectedVoice`, `TTSOnlineFallbackSettings.nghiVoice`
/// — đúng chuỗi `PiperTTSService` nhận); VieNeu = `"<model>:<giọng>"` như `VieNeuVoiceSelection.storageValue` (giọng Nano và
/// Turbo lưu riêng). Lưu một chuỗi JSON ở `defaultsKey` (hàng `TTSVolumeRow` quan sát bằng `@AppStorage`), chỉ ghi mục khác
/// mặc định. Đọc được ở mọi luồng (khoá tổng hợp tính ở luồng nền) — bảng giải mã đệm theo chuỗi thô.
///
/// Áp qua `TTSVolumeStage` (+ ghìm đỉnh `TTSPeakLimiter`) ở `PiperTTSService`, `VieNeuTTSEngine`, `VieNeuTurboTTSService`; vtts
/// đổi mức đích của `VttsLoudness`. Nằm trong `TTSSettingsSnapshot`, fingerprint giọng dự phòng và khoá tổng hợp
/// (`TTSSynthesisIdentity`, chỉ khi ≠ 0) ⇒ đổi mức là dựng lại đoạn.
enum TTSVolumeSettings {
    enum Engine: String, Sendable {
        case vtts
        case nghitts
        case vieneu
    }

    static let defaultsKey = "ttsVolumeOffsets"
    static let range: ClosedRange<Int> = -12...4

    /// Mặc định của giọng: 0, riêng giọng Google Dịch của vtts −3 dB.
    static func defaultOffset(engine: Engine, voiceKey: String) -> Int {
        engine == .vtts && voiceKey == VttsVoice.googleDich.id ? -3 : 0
    }

    /// Mức của giọng (khoá đã chuẩn — `voiceKey(engine:voice:)` / `vieNeuVoiceKey`).
    static func offset(engine: Engine, voiceKey: String) -> Int {
        table()[storageKey(engine, voiceKey)] ?? defaultOffset(engine: engine, voiceKey: voiceKey)
    }

    /// Mức của giọng `voice` (chuỗi như `selectedVoice` / tham số `voice` của service) với trình đọc `tool`; trình đọc
    /// không phải ba trình đọc offline ⇒ 0. VieNeu ghép model hiện hành.
    static func offset(forTool tool: String, voice: String) -> Int {
        guard let engine = Engine(rawValue: tool) else { return 0 }
        return offset(engine: engine, voiceKey: voiceKey(engine: engine, voice: voice))
    }

    static func voiceKey(engine: Engine, voice: String) -> String {
        switch engine {
        case .vtts: return VttsVoice.resolve(voice).id
        case .nghitts: return voice
        case .vieneu: return vieNeuVoiceKey(model: VieNeuModelChoice.current, voice: voice)
        }
    }

    static func vieNeuVoiceKey(model: VieNeuModelChoice, voice: String) -> String {
        "\(model.rawValue):\(voice)"
    }

    /// Ghi mức (kẹp `range`); bằng mặc định ⇒ xoá mục.
    static func set(_ value: Int, engine: Engine, voiceKey: String) {
        let clamped = min(range.upperBound, max(range.lowerBound, value))
        var entries = table()
        let key = storageKey(engine, voiceKey)
        if clamped == defaultOffset(engine: engine, voiceKey: voiceKey) {
            entries.removeValue(forKey: key)
        } else {
            entries[key] = clamped
        }
        let data = (try? JSONSerialization.data(withJSONObject: entries, options: [.sortedKeys])) ?? Data("{}".utf8)
        UserDefaults.standard.set(String(decoding: data, as: UTF8.self), forKey: defaultsKey)
    }

    // MARK: - Bảng lưu

    private static let lock = NSLock()
    private static var cachedRaw: String?
    private static var cachedTable: [String: Int] = [:]

    private static func storageKey(_ engine: Engine, _ voiceKey: String) -> String {
        "\(engine.rawValue)|\(voiceKey)"
    }

    private static func table() -> [String: Int] {
        let raw = UserDefaults.standard.string(forKey: defaultsKey) ?? ""
        lock.lock()
        defer { lock.unlock() }
        if raw == cachedRaw { return cachedTable }
        let decoded = (try? JSONSerialization.jsonObject(with: Data(raw.utf8))) as? [String: Any] ?? [:]
        cachedTable = decoded.compactMapValues { ($0 as? NSNumber)?.intValue }
        cachedRaw = raw
        return cachedTable
    }
}
