import Foundation

/// Cặp giọng **Nano ↔ Turbo** cho chế độ đọc lai (1.3.934). Các loại cặp:
/// - giọng có sẵn **trùng tên đúng từng chữ** ở hai model (`VieNeuBuiltinVoiceList`): Adam, Mai Anh, Trúc Ly, Anh Khôi,
///   Mạnh Dũng, Mỹ Duyên, Đức Trí. "Minh Quân" (Nano) và "Minh Quân Pro" (Turbo) **không** ghép — khác tên.
///   Mỹ Duyên / Đức Trí: nhãn Nano ghi giọng Bắc, nhãn Turbo ghi giọng Nam — vẫn ghép theo tên, nghe khác thì tắt công tắc;
/// - giọng nhân bản "Cả hai" / "Tạo bản Turbo": bản ghi Turbo có `sourceNanoVoiceId` = id bản ghi Nano (`VieNeuVoiceCloneFlow`);
/// - nhân bản chéo (1.3.937, `VieNeuVoiceCopyRunner`): bản ghi Turbo có `sourceNanoPresetName` = tên giọng Nano có sẵn, hoặc
///   bản ghi Nano có `sourceTurboVoiceId` = id giọng Turbo (có sẵn hoặc tự tạo) nó được nhân bản từ đó.
///
/// Luật tra nằm ở `resolve(model:voice:nanoCustom:turboCustom:)` (hàm thuần) — đọc lai và sheet chọn giọng
/// (`VieNeuVoiceDirectory`, giọng nào còn thiếu cặp) dùng chung.
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
        resolve(model: model, voice: voice, nanoCustom: nanoCustomRecords(), turboCustom: turboCustomRecords())
    }

    /// Cặp của một giọng, tra trên danh sách giọng tự tạo đã đọc sẵn — hàm thuần, gọi được ở mọi luồng.
    static func resolve(
        model: VieNeuModelChoice,
        voice: String,
        nanoCustom: [VieNeuCustomVoiceStore.Record],
        turboCustom: [VieNeuTurboCustomVoiceStore.Record]
    ) -> Pair? {
        guard !voice.isEmpty else { return nil }
        switch model {
        case .nano: return pairForNano(name: voice, nanoCustom: nanoCustom, turboCustom: turboCustom)
        case .turbo: return pairForTurbo(id: voice, nanoCustom: nanoCustom, turboCustom: turboCustom)
        }
    }

    private static func pairForNano(
        name: String,
        nanoCustom: [VieNeuCustomVoiceStore.Record],
        turboCustom: [VieNeuTurboCustomVoiceStore.Record]
    ) -> Pair? {
        if let record = nanoCustom.first(where: { $0.name == name }) {
            if let turbo = turboCustom.first(where: { $0.sourceNanoVoiceId == record.id }) {
                return Pair(nanoVoice: name, turboVoiceId: turbo.id, isCustom: true)
            }
            guard let turboId = record.sourceTurboVoiceId, turboVoiceExists(turboId, turboCustom: turboCustom) else { return nil }
            return Pair(nanoVoice: name, turboVoiceId: turboId, isCustom: true)
        }
        guard VieNeuBuiltinVoiceList.nano.contains(where: { $0.name == name }) else { return nil }
        if let turbo = VieNeuBuiltinVoiceList.turbo.first(where: { $0.name == name }) {
            return Pair(nanoVoice: name, turboVoiceId: turbo.id, isCustom: false)
        }
        guard let turbo = turboCustom.first(where: { $0.sourceNanoPresetName == name }) else { return nil }
        return Pair(nanoVoice: name, turboVoiceId: turbo.id, isCustom: true)
    }

    private static func pairForTurbo(
        id: String,
        nanoCustom: [VieNeuCustomVoiceStore.Record],
        turboCustom: [VieNeuTurboCustomVoiceStore.Record]
    ) -> Pair? {
        if VieNeuTurboModelStore.isCustomVoiceId(id) {
            guard let record = turboCustom.first(where: { $0.id == id }) else { return nil }
            if let nanoId = record.sourceNanoVoiceId, let nano = nanoCustom.first(where: { $0.id == nanoId }) {
                return Pair(nanoVoice: nano.name, turboVoiceId: id, isCustom: true)
            }
            if let preset = record.sourceNanoPresetName, VieNeuBuiltinVoiceList.nano.contains(where: { $0.name == preset }) {
                return Pair(nanoVoice: preset, turboVoiceId: id, isCustom: true)
            }
        } else if let turbo = VieNeuBuiltinVoiceList.turbo.first(where: { $0.id == id }),
                  VieNeuBuiltinVoiceList.nano.contains(where: { $0.name == turbo.name }) {
            return Pair(nanoVoice: turbo.name, turboVoiceId: id, isCustom: false)
        }
        guard let nano = nanoCustom.first(where: { $0.sourceTurboVoiceId == id }) else { return nil }
        return Pair(nanoVoice: nano.name, turboVoiceId: id, isCustom: true)
    }

    /// Giọng Turbo còn tồn tại: giọng có sẵn của danh sách dựng sẵn, hoặc bản ghi tự tạo còn trong kho.
    private static func turboVoiceExists(_ id: String, turboCustom: [VieNeuTurboCustomVoiceStore.Record]) -> Bool {
        VieNeuTurboModelStore.isCustomVoiceId(id)
            ? turboCustom.contains(where: { $0.id == id })
            : VieNeuBuiltinVoiceList.turbo.contains(where: { $0.id == id })
    }

    private static func nanoCustomRecords() -> [VieNeuCustomVoiceStore.Record] {
        VieNeuTTSService.shared?.customVoiceStore.loadLeniently() ?? []
    }

    private static func turboCustomRecords() -> [VieNeuTurboCustomVoiceStore.Record] {
        guard let store = VieNeuTurboTTSService.shared?.store else { return [] }
        return (try? VieNeuTurboCustomVoiceStore(modelStore: store).load()) ?? []
    }
}
