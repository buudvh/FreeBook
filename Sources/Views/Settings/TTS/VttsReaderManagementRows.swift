import SwiftUI

/// Hai hàng **từ điển phiên âm vtts** (1.3.1041, anh Bửu duyệt mockup) — dùng chung cho Cài đặt TTS (khi trình đọc là vtts)
/// và màn Giọng dự phòng (khi chọn vtts), đặt **bên trong** một `Section`, ngay trên hàng "Phiên âm tiếng Nhật":
/// lối vào `VttsPhoneticDictionaryView` + công tắc "Áp dụng từ điển phiên âm vtts" (`VttsPhoneticDictionary.enabledKey`,
/// mặc định bật). Công tắc nằm trong `TTSSettingsSnapshot` + fingerprint giọng dự phòng ⇒ đổi rồi đóng Cài đặt là dựng
/// lại đoạn.
struct VttsReaderManagementRows: View {
    @AppStorage(VttsPhoneticDictionary.enabledKey) private var dictionaryEnabled = true

    /// Đoạn giải thích sau nút "?" của tiêu đề section khi chọn vtts.
    static let helpParagraphs: [LocalizedStringKey] = [
        "**Từ điển phiên âm vtts**: từ gốc → cách đọc tiếng Việt, riêng cho vtts (không đụng từ điển NghiTTS / VieNeu). Áp trước \"Phiên âm tiếng Nhật\" nên mục anh tự thêm luôn thắng. Thêm nhanh: bôi đen một từ trong truyện › **Phiên âm** › **Lưu vào vtts**.",
        TTSJapaneseTransliterationRow.helpParagraph(forTool: TTSJapaneseTransliterationSettings.vttsTool)
    ]

    var body: some View {
        NavigationLink(destination: VttsPhoneticDictionaryView()) {
            Label("Từ điển phiên âm vtts", systemImage: "character.book.closed")
        }
        Toggle("Áp dụng từ điển phiên âm vtts", isOn: $dictionaryEnabled)
    }
}
