import Foundation

/// Chọn engine on-device cho nhánh `tool == "nghitts"`.
///
/// Nhánh `nghitts` mang **hai** engine chứ không phải một: `piper` (VITS/ONNX, 22.05 kHz) và
/// `vieneu` (VieNeu-TTS v3 Turbo, tự hồi quy, 48 kHz).
///
/// Vì sao là sub-selection chứ không phải một giá trị `tool` thứ năm: chuỗi `"nghitts"` được so sánh
/// ở khoảng 45 chỗ trong `TTSManager` cộng `TTSChapterPrefetcher`, `TTSNextChapterPrefixCache`,
/// `TTSManager+PrefetchCache`, `TTSManager+NextChapterPrefix` — nó là proxy cho "engine chạy trên
/// máy" và điều khiển toàn bộ policy prefetch, trim cache, next-chapter prefix, energy log, cùng
/// phép phân loại remote (`isRemoteTTS = tool != "system" && tool != "nghitts"`). Thêm một `tool`
/// mới buộc phải rà lại cả 45 nhánh đó, và bỏ sót một chỗ là VieNeu bị xếp vào nhóm remote. Giữ
/// `"nghitts"` thì mọi policy được thừa hưởng nguyên vẹn.
///
/// `nghiEngineKind` và `vieNeuVoiceName` cố ý là **computed property đọc/ghi UserDefaults** thay vì
/// `@Published`: `TTSManager.swift` đã vượt baseline dòng của `check_architecture.py`, nên phần thêm
/// mới nằm ở file này. View vẫn cập nhật đúng vì setter gọi `objectWillChange.send()`.
extension TTSManager {
    enum LocalEngineKind: String, CaseIterable {
        case piper
        case vieneu

        var displayName: String {
            switch self {
            case .piper: return "Piper (nhẹ, 22 kHz)"
            case .vieneu: return "VieNeu v3 Turbo (48 kHz)"
            }
        }
    }

    static let nghiEngineKindKey = "nghiEngineKind"

    var nghiEngineKind: String {
        get {
            guard let stored = UserDefaults.standard.string(forKey: Self.nghiEngineKindKey),
                  LocalEngineKind(rawValue: stored) != nil else {
                return LocalEngineKind.piper.rawValue
            }
            return stored
        }
        set {
            guard newValue != nghiEngineKind, LocalEngineKind(rawValue: newValue) != nil else { return }
            objectWillChange.send()
            UserDefaults.standard.set(newValue, forKey: Self.nghiEngineKindKey)
            applyLocalEngineChange()
        }
    }

    var localEngineKind: LocalEngineKind {
        LocalEngineKind(rawValue: nghiEngineKind) ?? .piper
    }

    /// Giọng của VieNeu lưu **riêng** dưới `VieNeuTTSService.voiceKey`, không dùng chung
    /// `selectedVoice` với Piper: hai bộ tên không giao nhau nên dùng chung một khoá là đổi engine
    /// xong không còn giọng hợp lệ.
    var vieNeuVoiceName: String {
        get { UserDefaults.standard.string(forKey: VieNeuTTSService.voiceKey) ?? "" }
        set {
            guard newValue != vieNeuVoiceName else { return }
            objectWillChange.send()
            UserDefaults.standard.set(newValue, forKey: VieNeuTTSService.voiceKey)
            clearPrefetchCache()
        }
    }

    /// Giọng thật sự đưa xuống engine on-device đang chọn.
    var activeLocalVoiceName: String {
        switch localEngineKind {
        case .piper: return selectedVoice
        case .vieneu:
            let stored = vieNeuVoiceName
            if !stored.isEmpty { return stored }
            return (nghiTTSService as? VieNeuTTSService)?.defaultVoiceName ?? ""
        }
    }

    /// Dựng service cho engine đang chọn.
    ///
    /// Trả `nil` khi chọn VieNeu mà chưa dựng được store — call site phải để `nghiTTSService` là
    /// `nil` chứ **không** được lặng lẽ rơi về Piper: người dùng chọn VieNeu thì phải nghe VieNeu
    /// hoặc thấy lỗi, không phải nghe giọng khác mà không hiểu vì sao.
    func makeLocalTTSService(modelStore: ModelStore) -> (any LocalTTSSynthesizing)? {
        switch localEngineKind {
        case .piper:
            return PiperTTSService(modelStore: modelStore, engine: ONNXPiperEngine())
        case .vieneu:
            guard let store = VieNeuModelStore.shared else {
                AppLogger.shared.log("🗣️ [TTSManager] Không dựng được VieNeuModelStore, engine VieNeu không khả dụng")
                return nil
            }
            return VieNeuTTSService(store: store)
        }
    }

    /// Đổi engine giữa phiên: dừng phát, xoá cache audio, dựng lại service.
    ///
    /// Bắt buộc xoá cache: hai engine cho sample rate khác nhau (22.05 kHz và 48 kHz) và giọng khác
    /// nhau, nên payload PCM còn lại của engine cũ vừa sai giọng vừa sai tần số.
    func applyLocalEngineChange() {
        stop()
        clearPrefetchCache()
        rebuildLocalTTSService()
    }

    func rebuildLocalTTSService() {
        guard let modelStore = try? ModelStore() else {
            AppLogger.shared.log("🗣️ [TTSManager] Không dựng được ModelStore khi đổi engine on-device")
            return
        }
        nghiTTSService = makeLocalTTSService(modelStore: modelStore)
        let kind = localEngineKind
        let voice = activeLocalVoiceName
        AppLogger.shared.log("🗣️ [TTSManager] Engine on-device = \(kind.rawValue), giọng = '\(voice)'")

        guard let service = nghiTTSService, tool == "nghitts" else { return }
        Task.detached(priority: .utility) {
            try? await service.prepare(voice: voice)
        }
    }

    /// Bộ model VieNeu đã cài đủ chưa. Dùng ở màn Cài đặt và ở chốt trước khi phát.
    var isVieNeuModelInstalled: Bool {
        VieNeuModelStore.shared?.isInstalled ?? false
    }

    /// Danh sách giọng preset của VieNeu, rỗng khi chưa tải model.
    var vieNeuVoices: [VieNeuVoice] {
        (nghiTTSService as? VieNeuTTSService)?.voices ?? []
    }
}
