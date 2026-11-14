import Foundation

/// Cặp giọng **Nano ↔ Turbo** cho chế độ đọc lai (1.3.934). Chỉ hai loại cặp (anh Bửu chốt):
/// - giọng có sẵn **trùng tên đúng từng chữ** ở hai model (`VieNeuBuiltinVoiceList`): Adam, Mai Anh, Trúc Ly, Anh Khôi,
///   Mạnh Dũng, Mỹ Duyên, Đức Trí. "Minh Quân" (Nano) và "Minh Quân Pro" (Turbo) **không** ghép — khác tên.
///   Mỹ Duyên / Đức Trí: nhãn Nano ghi giọng Bắc, nhãn Turbo ghi giọng Nam — vẫn ghép theo tên, nghe khác thì tắt công tắc;
/// - giọng nhân bản "Cả hai": bản ghi Turbo có `sourceNanoVoiceId` = id bản ghi Nano (`VieNeuVoiceCloneFlow`).
///
/// Đọc hai file `voices_custom.json` ⇒ có đệm: một kết quả giữ 30 s (kể cả "không có cặp") — giọng mới tạo bản Turbo
/// ("Tạo bản Turbo") được nhận sau tối đa 30 s, không phải mở lại app. Chỉ **đọc**, không ghi ⇒ an toàn ngoài `MainActor`
/// (hai kho ghi nguyên tử bằng `replaceItemAt`).
final class VieNeuVoicePairing: @unchecked Sendable {
    struct Pair: Hashable, Sendable {
        /// `Voice.name` của Nano (engine Nano tra giọng theo tên).
        let nanoVoice: String
        /// Id giọng Turbo (id manifest hoặc `custom_…`).
        let turboVoiceId: String
        /// `true` = giọng nhân bản "Cả hai"; `false` = giọng có sẵn trùng tên.
        let isCustom: Bool
    }

    static let shared = VieNeuVoicePairing()

    private static let cacheLifetime: TimeInterval = 30
    private let lock = NSLock()
    private var cache: [String: (pair: Pair?, at: TimeInterval)] = [:]

    /// Cặp của giọng **đang dùng** của một model (`voice` = `TTSManager.selectedVoice` khi model đó đang đọc).
    func pair(model: VieNeuModelChoice, voice: String) -> Pair? {
        let key = "\(model.rawValue):\(voice)"
        let now = ProcessInfo.processInfo.systemUptime
        lock.lock()
        if let hit = cache[key], now - hit.at < Self.cacheLifetime {
            lock.unlock()
            return hit.pair
        }
        lock.unlock()
        let resolved = Self.resolve(model: model, voice: voice)
        lock.lock()
        if cache.count > 32 { cache.removeAll() }
        cache[key] = (resolved, now)
        lock.unlock()
        return resolved
    }

    /// Bỏ đệm — gọi khi đổi công tắc ở Cài đặt (để dòng trạng thái và lượt đọc kế tiếp thấy ngay giọng vừa tạo).
    func invalidate() {
        lock.lock()
        cache.removeAll()
        lock.unlock()
    }

    // MARK: - Tra cặp

    private static func resolve(model: VieNeuModelChoice, voice: String) -> Pair? {
        guard !voice.isEmpty else { return nil }
        switch model {
        case .nano: return pairForNano(name: voice)
        case .turbo: return pairForTurbo(id: voice)
        }
    }

    private static func pairForNano(name: String) -> Pair? {
        if let record = nanoCustomRecords().first(where: { $0.name == name }) {
            guard let turbo = turboCustomRecords().first(where: { $0.sourceNanoVoiceId == record.id }) else { return nil }
            return Pair(nanoVoice: name, turboVoiceId: turbo.id, isCustom: true)
        }
        guard VieNeuBuiltinVoiceList.nano.contains(where: { $0.name == name }),
              let turbo = VieNeuBuiltinVoiceList.turbo.first(where: { $0.name == name }) else { return nil }
        return Pair(nanoVoice: name, turboVoiceId: turbo.id, isCustom: false)
    }

    private static func pairForTurbo(id: String) -> Pair? {
        if VieNeuTurboModelStore.isCustomVoiceId(id) {
            guard let record = turboCustomRecords().first(where: { $0.id == id }),
                  let nanoId = record.sourceNanoVoiceId,
                  let nano = nanoCustomRecords().first(where: { $0.id == nanoId }) else { return nil }
            return Pair(nanoVoice: nano.name, turboVoiceId: id, isCustom: true)
        }
        guard let turbo = VieNeuBuiltinVoiceList.turbo.first(where: { $0.id == id }),
              VieNeuBuiltinVoiceList.nano.contains(where: { $0.name == turbo.name }) else { return nil }
        return Pair(nanoVoice: turbo.name, turboVoiceId: id, isCustom: false)
    }

    private static func nanoCustomRecords() -> [VieNeuCustomVoiceStore.Record] {
        VieNeuTTSService.shared?.customVoiceStore.loadLeniently() ?? []
    }

    private static func turboCustomRecords() -> [VieNeuTurboCustomVoiceStore.Record] {
        guard let store = VieNeuTurboTTSService.shared?.store else { return [] }
        return (try? VieNeuTurboCustomVoiceStore(modelStore: store).load()) ?? []
    }
}
