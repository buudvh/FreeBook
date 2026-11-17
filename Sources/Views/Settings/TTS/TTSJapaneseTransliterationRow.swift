import SwiftUI

/// Hàng công tắc **"Phiên âm tiếng Nhật"** — có ở **mọi** trình đọc, giá trị lưu **riêng từng trình đọc** (1.3.973, anh
/// Bửu: "sửa lại nút phiên âm tiếng nhật cho tất cả tts, config lưu riêng mỗi loại tts").
///
/// `tool` đúng bằng `TTSManager.tool` (`system` / `nghitts` / `vieneu` / `google` / `packageId` của tiện ích TTS). Đặt
/// **bên trong** một `Section`: Cài đặt TTS › "Quản lý riêng của trình đọc" (mọi trình đọc; VieNeu qua
/// `VieNeuReaderManagementRows`), màn Giọng dự phòng, và "Tiền xử lý text" của Cấu hình NghiTTS.
///
/// Giá trị thật nằm ở `TTSJapaneseTransliterationSettings`. `@State` chỉ khởi tạo một lần lúc View dựng nên đọc lại
/// mỗi lần hàng hiện và mỗi lần `tool` đổi (bài học 1.3.456) — chuyển trình đọc là công tắc hiện đúng giá trị của nó.
struct TTSJapaneseTransliterationRow: View {
    let tool: String
    @State private var isOn: Bool

    init(tool: String) {
        self.tool = tool
        _isOn = State(initialValue: TTSJapaneseTransliterationSettings.isEnabled(forTool: tool))
    }

    var body: some View {
        Toggle("Phiên âm tiếng Nhật", isOn: Binding(
            get: { isOn },
            set: { newValue in
                isOn = newValue
                TTSJapaneseTransliterationSettings.setEnabled(newValue, forTool: tool)
                AppLogger.shared.log("[TTSSettings] Phiên âm tiếng Nhật (\(tool)): \(newValue ? "bật" : "tắt")")
            }
        ))
        .onAppear { isOn = TTSJapaneseTransliterationSettings.isEnabled(forTool: tool) }
        .onChange(of: tool) { _, newTool in
            isOn = TTSJapaneseTransliterationSettings.isEnabled(forTool: newTool)
        }
    }

    /// Đoạn giải thích sau nút "?" của tiêu đề "Quản lý riêng của trình đọc" — mỗi trình đọc phiên âm một kiểu.
    static func helpParagraph(forTool tool: String) -> LocalizedStringKey {
        switch tool {
        case TTSJapaneseTransliterationSettings.nghiTool:
            return "**Phiên âm tiếng Nhật**: chữ kana và từ romaji (Sakura, arigatou) đọc theo âm tiết Việt. Lưu riêng cho NghiTTS; từ nước ngoài khác theo công tắc **Phiên âm tiếng Anh** ở Cấu hình tiền xử lý."
        case TTSJapaneseTransliterationSettings.vieNeuTool:
            return "**Phiên âm tiếng Nhật**: tên kiểu Nhật viết hoa (Sasuke, Naruto-kun) đọc theo từng âm tiết thay vì theo luật tiếng Anh. Lưu riêng cho VieNeu, chung Nano và Turbo."
        default:
            return "**Phiên âm tiếng Nhật**: chữ kana và từ romaji (Sakura → Xa cư ra) được đổi sang âm tiết Việt trước khi đưa cho giọng đọc. Lưu riêng cho từng trình đọc, mặc định tắt ở trình đọc này."
        }
    }
}
