import Foundation

/// **Âm lượng theo giọng** của ba trình đọc offline — vtts, NghiTTS, VieNeu (1.3.1047, anh Bửu: "thêm config tăng âm lượng"
/// → "Làm cho cả ba", duyệt mockup https://claude.ai/artifact/SiAJyQbt7tgWohnCJesDcg). Giá trị = số dB to / nhỏ hơn mức app
/// vẫn kéo cho giọng đó (0 = như trước 1.3.1047), lưu riêng từng cặp trình đọc + giọng, kẹp `range`.
///
/// Vì sao vtts mặc định −6 dB (1.3.1048, anh Bửu: "vtts giảm âm lượng vẫn bị rè, tất cả giọng đều có độ rè"): trong bộ nghe
/// thử 2026-11-23, bản anh nghe rè đúng là bản bộ ghìm đỉnh phải cắt (đỉnh chạm −1 dBFS ở mốc −14 dB của `VttsLoudness`);
/// bản −17 / −20 dB — kể cả bản có đủ lọc + nâng 2,8 kHz — không chạm trần, không rè. Log máy anh ở −14 dB: ghìm tới −5,5 dB
/// ở đoạn đỉnh cao ⇒ −3 dB (mặc định của Google Dịch ở 1.3.1047) chưa đủ, −6 dB thì bộ ghìm gần như không chạm. Mức −20 dBFS
/// vẫn to hơn tiếng gốc của model (≈ −7 … −10,5 dB trên thang này) và nhỏ hơn Google online (≈ −4 dB) khoảng 2 dB.
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

    /// Mặc định của mọi giọng vtts (kể cả giọng tự nhập) từ 1.3.1048 — lý do ở đầu file.
    static let vttsDefaultOffset = -6

    /// Mặc định của giọng: vtts `vttsDefaultOffset`, NghiTTS / VieNeu 0.
    static func defaultOffset(engine: Engine, voiceKey: String) -> Int {
        engine == .vtts ? vttsDefaultOffset : 0
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
        write(entries)
    }

    // MARK: - Bảng lưu

    private static let lock = NSLock()
    private static var cachedRaw: String?
    private static var cachedTable: [String: Int] = [:]

    private static func storageKey(_ engine: Engine, _ voiceKey: String) -> String {
        "\(engine.rawValue)|\(voiceKey)"
    }

    private static func table() -> [String: Int] {
        _ = vttsDefaultMigration
        let raw = UserDefaults.standard.string(forKey: defaultsKey) ?? ""
        lock.lock()
        defer { lock.unlock() }
        if raw == cachedRaw { return cachedTable }
        cachedTable = decode(raw)
        cachedRaw = raw
        return cachedTable
    }

    private static func decode(_ raw: String) -> [String: Int] {
        let decoded = (try? JSONSerialization.jsonObject(with: Data(raw.utf8))) as? [String: Any] ?? [:]
        return decoded.compactMapValues { ($0 as? NSNumber)?.intValue }
    }

    private static func write(_ entries: [String: Int]) {
        let data = (try? JSONSerialization.data(withJSONObject: entries, options: [.sortedKeys])) ?? Data("{}".utf8)
        UserDefaults.standard.set(String(decoding: data, as: UTF8.self), forKey: defaultsKey)
    }

    // MARK: - Chuyển bảng cũ

    /// Đã chuyển bảng sang mặc định vtts −6 dB (1.3.1048).
    private static let vttsDefaultMigrationKey = "ttsVolumeOffsetsVttsDefaultMinus6"

    /// Chạy một lần mỗi máy, ở lần đọc bảng đầu tiên (`static let` khởi tạo lười, an toàn đa luồng): mục vtts anh đã chỉnh
    /// **to hơn** −6 dB (kể cả 0 / −3 của 1.3.1047) bị bỏ ⇒ về mặc định mới; mục nhỏ hơn giữ nguyên. NghiTTS / VieNeu không đụng.
    private static let vttsDefaultMigration: Void = {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: TTSVolumeSettings.vttsDefaultMigrationKey) else { return }
        defer { defaults.set(true, forKey: TTSVolumeSettings.vttsDefaultMigrationKey) }
        guard let raw = defaults.string(forKey: TTSVolumeSettings.defaultsKey) else { return }
        let entries = TTSVolumeSettings.decode(raw)
        let prefix = "\(Engine.vtts.rawValue)|"
        let kept = entries.filter { key, value in !key.hasPrefix(prefix) || value < TTSVolumeSettings.vttsDefaultOffset }
        guard kept.count != entries.count else { return }
        TTSVolumeSettings.write(kept)
        let dropped = entries.count - kept.count
        AppLogger.shared.log("🔊 [TTSVolume] Mặc định vtts \(TTSVolumeSettings.vttsDefaultOffset) dB: bỏ \(dropped) mục to hơn")
    }()
}
