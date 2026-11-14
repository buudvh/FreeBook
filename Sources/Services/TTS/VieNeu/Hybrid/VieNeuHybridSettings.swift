import Foundation

/// Hai công tắc **đọc lai Nano · Turbo** (1.3.934) ở Cài đặt TTS (1.3.943), mặc định **bật** (thiếu khoá = bật).
///
/// - `languageKey` — phương án A: giọng **Nano** có cặp Turbo ⇒ đoạn có tiếng nước ngoài (thực tế là tiếng Anh) đọc Turbo.
/// - `thermalKey` — phương án B: giọng **Turbo** có cặp Nano ⇒ máy nóng thì đọc Nano, mát lại về Turbo.
///
/// Hàm thuần `UserDefaults` ⇒ gọi được ngoài `MainActor` (khoá tổng hợp, định tuyến từng lượt tổng hợp).
enum VieNeuHybridSettings {
    static let languageKey = "vieneuHybridLanguageEnabled"
    static let thermalKey = "vieneuHybridThermalEnabled"

    static var isLanguageRoutingEnabled: Bool { flag(languageKey) }
    static var isThermalRoutingEnabled: Bool { flag(thermalKey) }

    private static func flag(_ key: String) -> Bool {
        UserDefaults.standard.object(forKey: key) == nil ? true : UserDefaults.standard.bool(forKey: key)
    }
}
