import Foundation

/// **Giọng VieNeu đang chọn kèm model** (1.3.898) — người dùng chọn giọng, model đi theo giọng: giọng Nano ⇒ trình đọc
/// chạy Nano (ONNX), giọng Turbo ⇒ Turbo (GGUF qua audio.cpp). Không còn chọn model riêng ở Picker "Trình đọc".
///
/// ## Lưu ở đâu
/// Một khoá `vieneuSelectedVoice`, giá trị `"nano:<tên giọng Nano>"` hoặc `"turbo:<id giọng Turbo>"`. Tên giọng Nano là
/// `Voice.name` (engine Nano tra giọng theo tên); id Turbo là id manifest hoặc `custom_…`. `voiceId` rỗng = giọng mặc
/// định của model.
///
/// Thêm khoá phụ `vieneuVoice` (khoá cũ của Nano) — **giọng Nano dùng gần nhất**: lúc Turbo không chạy được trên máy
/// (thiếu file / bản build không có audio.cpp) trình đọc lùi về Nano bằng giọng này thay vì giọng mặc định.
///
/// ## Lùi về Nano không được xoá lựa chọn Turbo
/// `VieNeuModelChoice.current` lùi về Nano khi Turbo không sẵn sàng; lúc đó `TTSManager.applyVieNeuParamsIfNeeded` gán
/// một giọng Nano và `persistVoice` chạy. Nếu `persistVoice` ghi đè khoá này bằng model **hiệu lực** thì một lần thiếu
/// file GGUF là mất hẳn lựa chọn Turbo. Nên chỉ ghi khi model hiệu lực **trùng** model đã lưu
/// (`recordReaderVoice(_:effectiveModel:)`).
///
/// ## Chuyển từ khoá cũ (trước 1.3.898)
/// `vieneuModel` ("nano"/"turbo") + `vieneuVoice` (giọng Nano) + `vieneuTurboVoice` (giọng Turbo) ⇒ một lựa chọn, ghi
/// một lần khi khoá mới chưa có. Khoá cũ **giữ nguyên**, không xoá (bản cũ của app / bản sao lưu cũ vẫn đọc được).
struct VieNeuVoiceSelection: Hashable, Sendable {
    let model: VieNeuModelChoice
    /// Nano: `Voice.name`; Turbo: id manifest / `custom_…`. Rỗng = giọng mặc định của model.
    let voiceId: String

    static let defaultsKey = "vieneuSelectedVoice"
    /// Khoá cũ của Nano — từ 1.3.898 là "giọng Nano dùng gần nhất" (xem doc của type).
    static let lastNanoVoiceKey = "vieneuVoice"
    /// Khoá cũ, chỉ đọc khi chuyển dữ liệu.
    static let legacyModelKey = "vieneuModel"
    static let legacyTurboVoiceKey = "vieneuTurboVoice"

    init(model: VieNeuModelChoice, voiceId: String) {
        self.model = model
        self.voiceId = voiceId
    }

    /// Giọng mặc định của Nano — dùng khi không còn gì để chọn (vd vừa xoá model Turbo).
    static let nanoDefault = VieNeuVoiceSelection(model: .nano, voiceId: "")

    // MARK: - Mã hoá

    var storageValue: String { "\(model.rawValue):\(voiceId)" }

    init?(storageValue: String) {
        guard let separator = storageValue.firstIndex(of: ":"),
              let model = VieNeuModelChoice(rawValue: String(storageValue[..<separator])) else { return nil }
        self.init(model: model, voiceId: String(storageValue[storageValue.index(after: separator)...]))
    }

    /// Khoá so sánh dùng chung cho UI (hàng đang chọn, hàng đang phát thử): `"turbo:minh_quan_pro"`.
    var key: String { storageValue }

    // MARK: - Đọc / ghi

    /// Lựa chọn đã lưu (chưa xét máy có chạy được model đó không). Chưa có khoá mới ⇒ chuyển từ khoá cũ rồi ghi lại.
    /// Hàm thuần `UserDefaults` ⇒ gọi được ngoài `MainActor` (khoá tổng hợp tính ở luồng nền).
    static var stored: VieNeuVoiceSelection {
        let defaults = UserDefaults.standard
        if let raw = defaults.string(forKey: defaultsKey), let selection = VieNeuVoiceSelection(storageValue: raw) {
            return selection
        }
        let migrated = migratedFromLegacyKeys(defaults)
        defaults.set(migrated.storageValue, forKey: defaultsKey)
        AppLogger.shared.log("[TTSRoute] chuyen giong VieNeu tu khoa cu => \(migrated.storageValue)")
        return migrated
    }

    static func store(_ selection: VieNeuVoiceSelection) {
        UserDefaults.standard.set(selection.storageValue, forKey: defaultsKey)
        if selection.model == .nano, !selection.voiceId.isEmpty {
            UserDefaults.standard.set(selection.voiceId, forKey: lastNanoVoiceKey)
        }
    }

    /// Giọng Nano dùng gần nhất (`nil` = chưa từng chọn ⇒ giọng mặc định).
    static var lastNanoVoice: String? {
        UserDefaults.standard.string(forKey: lastNanoVoiceKey).flatMap { $0.isEmpty ? nil : $0 }
    }

    /// `TTSManager.persistVoice` gọi mỗi khi giọng của trình đọc đổi. Model hiệu lực khác model đã lưu (đang lùi về Nano)
    /// ⇒ chỉ nhớ giọng Nano gần nhất, **không** đụng lựa chọn Turbo đã lưu.
    static func recordReaderVoice(_ voiceId: String, effectiveModel: VieNeuModelChoice) {
        if effectiveModel == stored.model {
            store(VieNeuVoiceSelection(model: effectiveModel, voiceId: voiceId))
        } else if effectiveModel == .nano, !voiceId.isEmpty {
            UserDefaults.standard.set(voiceId, forKey: lastNanoVoiceKey)
        }
    }

    private static func migratedFromLegacyKeys(_ defaults: UserDefaults) -> VieNeuVoiceSelection {
        let model = defaults.string(forKey: legacyModelKey).flatMap(VieNeuModelChoice.init(rawValue:)) ?? .nano
        switch model {
        case .nano:
            return VieNeuVoiceSelection(model: .nano, voiceId: defaults.string(forKey: lastNanoVoiceKey) ?? "")
        case .turbo:
            let voice = defaults.string(forKey: legacyTurboVoiceKey) ?? VieNeuTurboModelStore.fallbackVoiceId
            return VieNeuVoiceSelection(model: .turbo, voiceId: voice)
        }
    }
}
