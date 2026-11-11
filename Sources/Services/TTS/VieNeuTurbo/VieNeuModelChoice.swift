import Foundation

/// Model VieNeu mà **trình đọc** dùng khi `tool == "vieneu"`: Nano (ONNX, `VieNeuTTSService`) hay Turbo (GGUF qua
/// audio.cpp, `VieNeuTurboTTSService`).
///
/// ## Vì sao không thêm chuỗi `tool` mới
/// `tool` được so sánh chuỗi ở nhiều chỗ (`isExtensionTool`, `isLocalEngine`, ba hàm `persist*`, `currentPrefetchCount`
/// … — xem bẫy "6 chỗ" ở `TTSManager+VieNeu.swift`). Một `tool` thứ hai cho Turbo là phải sửa đủ mọi chỗ, sót một là
/// Turbo rơi vào nhánh extension. Nên `tool` vẫn là `"vieneu"`, còn model lưu riêng ở khoá `vieneuModel`; Picker
/// "Trình đọc" ánh xạ hai tag UI (`"vieneu"` / `turboPickerTag`) về đây.
///
/// ## Model **hiệu lực** (`current`) khác model **đã lưu** (`stored`)
/// Turbo chỉ tính khi bản build có audio.cpp **và** máy đủ model + manifest giọng + `sea_g2p.bin`. Thiếu một thứ (ví dụ
/// vừa "Xoá model" ở màn thử) thì trình đọc rơi về Nano thay vì đọc lỗi từng đoạn. Hàm thuần `UserDefaults` + kiểm file
/// nên gọi được ngoài `MainActor` (khoá tổng hợp, tốc độ tổng hợp — tính ở luồng nền).
enum VieNeuModelChoice: String, CaseIterable, Sendable {
    case nano
    case turbo

    static let defaultsKey = "vieneuModel"
    /// Giọng Turbo nhớ riêng — Nano giữ khoá cũ `vieneuVoice` (`TTSManager.VieNeuSettingsKey.voice`).
    static let turboVoiceKey = "vieneuTurboVoice"
    /// Tag của mục Turbo trong Picker "Trình đọc". Chỉ sống ở tầng UI — **không bao giờ** được ghi vào `tool`.
    static let turboPickerTag = "vieneu#turbo"
    private static let vieNeuTool = "vieneu"

    /// Lựa chọn đã lưu, chưa xét máy có đủ file hay không.
    static var stored: VieNeuModelChoice {
        UserDefaults.standard.string(forKey: defaultsKey).flatMap(VieNeuModelChoice.init(rawValue:)) ?? .nano
    }

    static func store(_ model: VieNeuModelChoice) {
        UserDefaults.standard.set(model.rawValue, forKey: defaultsKey)
    }

    /// Model trình đọc thật sự dùng — xem doc của type.
    static var current: VieNeuModelChoice {
        stored == .turbo && VieNeuTurboTTSService.isReadyOnDisk ? .turbo : .nano
    }

    /// Khoá `UserDefaults` lưu giọng của model này.
    var voiceDefaultsKey: String {
        switch self {
        case .nano: return TTSManager.VieNeuSettingsKey.voice
        case .turbo: return Self.turboVoiceKey
        }
    }

    /// Tên engine đưa vào **khoá tổng hợp** (`TTSSynthesisIdentity`). Nano giữ nguyên `"vieneu"` để khoá cũ không đổi;
    /// Turbo thành `"vieneu.turbo"` ⇒ đổi model không bao giờ phát lại audio của model kia.
    static func synthesisEngineIdentity(forEngine engine: String) -> String {
        engine == vieNeuTool && current == .turbo ? "vieneu.turbo" : engine
    }

    /// Tag Picker "Trình đọc" của `tool` đang chọn.
    static func pickerTag(forTool tool: String) -> String {
        tool == vieNeuTool && current == .turbo ? turboPickerTag : tool
    }

    /// Model ứng với một tag Picker; `nil` = tag của trình đọc khác (gán thẳng vào `tool`).
    init?(pickerTag: String) {
        switch pickerTag {
        case Self.vieNeuTool: self = .nano
        case Self.turboPickerTag: self = .turbo
        default: return nil
        }
    }
}
