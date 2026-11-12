import Foundation

/// Model VieNeu mà **trình đọc** dùng khi `tool == "vieneu"`: Nano (ONNX, `VieNeuTTSService`) hay Turbo (GGUF qua
/// audio.cpp, `VieNeuTurboTTSService`).
///
/// ## Model đi theo giọng (1.3.897)
/// Không còn chọn model riêng: model là phần của giọng đang chọn (`VieNeuVoiceSelection`, khoá `vieneuSelectedVoice`).
/// Picker "Trình đọc" chỉ còn một mục VieNeu (`tool = "vieneu"`), chọn giọng ở sheet "Giọng đọc".
///
/// ## Vì sao không thêm chuỗi `tool` mới
/// `tool` được so sánh chuỗi ở nhiều chỗ (`isExtensionTool`, `isLocalEngine`, ba hàm `persist*`, `currentPrefetchCount`
/// … — xem bẫy "6 chỗ" ở `TTSManager+VieNeu.swift`). Một `tool` thứ hai cho Turbo là phải sửa đủ mọi chỗ, sót một là
/// Turbo rơi vào nhánh extension. Nên `tool` vẫn là `"vieneu"`, model nằm trong lựa chọn giọng.
///
/// ## Model **hiệu lực** (`current`) khác model **đã lưu** (`stored`)
/// Turbo chỉ tính khi bản build có audio.cpp **và** máy đủ model + manifest giọng + `sea_g2p.bin`. Thiếu một thứ (ví dụ
/// vừa "Xoá model" ở màn thử) thì trình đọc rơi về Nano thay vì đọc lỗi từng đoạn. Hàm thuần `UserDefaults` + kiểm file
/// nên gọi được ngoài `MainActor` (khoá tổng hợp, tốc độ tổng hợp — tính ở luồng nền).
enum VieNeuModelChoice: String, CaseIterable, Sendable {
    case nano
    case turbo

    private static let vieNeuTool = "vieneu"

    /// Model của giọng đã lưu, chưa xét máy có đủ file hay không.
    static var stored: VieNeuModelChoice {
        VieNeuVoiceSelection.stored.model
    }

    /// Model trình đọc thật sự dùng — xem doc của type.
    static var current: VieNeuModelChoice {
        stored == .turbo && VieNeuTurboTTSService.isReadyOnDisk ? .turbo : .nano
    }

    /// Nhãn nhỏ cạnh tên giọng ("Nano" / "Turbo").
    var label: String {
        switch self {
        case .nano: return "Nano"
        case .turbo: return "Turbo"
        }
    }

    /// Tên engine đưa vào **khoá tổng hợp** (`TTSSynthesisIdentity`). Nano giữ nguyên `"vieneu"` để khoá cũ không đổi;
    /// Turbo thành `"vieneu.turbo"` ⇒ đổi model không bao giờ phát lại audio của model kia.
    static func synthesisEngineIdentity(forEngine engine: String) -> String {
        engine == vieNeuTool && current == .turbo ? "vieneu.turbo" : engine
    }
}
