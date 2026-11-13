import SwiftUI

/// Hub **"Cài đặt NghiTTS"** — một chỗ cho mọi thứ thuộc engine NghiTTS (Piper): hàng "Giọng đọc NghiTTS" (mở sheet chọn
/// giọng chung — tải / thử / xoá / nhập giọng ở đó), thông tin model (engine, giọng đã tải, thư viện phiên âm), danh sách
/// giọng đã tải kèm dung lượng, và lối vào từ điển phiên âm + cấu hình tiền xử lý.
///
/// Dung lượng đọc đĩa ở nền (`ModelSnapshot`, `.task` + `Task.detached`), không trong `body`; `.task` chạy lại mỗi lần
/// màn hiện ra, và đọc lại khi sheet chọn giọng đóng ⇒ số liệu theo kịp lượt tải / xoá.
struct NghiTTSSettingsHubView: View {
    @State var snapshot: ModelSnapshot?
    /// Sheet chọn giọng NghiTTS (`.nghi` = đang mở).
    @State var voicePicker: TTSVoiceEngine?
    /// Tăng khi sheet chọn giọng đóng ⇒ `body` đọc lại giọng đang dùng (không observe `TTSManager`).
    @State var selectionToken = 0

    var body: some View {
        Form { Group {
            voiceSection
            modelSection
            voicesSection
            managementSection
        }.glassSheetRows() }
        .backPageTitle("Cài đặt NghiTTS")
        .task { await reloadSnapshot() }
        .ttsVoicePickerSheet(engine: $voicePicker) {
            selectionToken += 1
            Task { await reloadSnapshot() }
        }
    }

    private func reloadSnapshot() async {
        let loaded = await Task.detached(priority: .userInitiated) {
            Self.loadModelSnapshot()
        }.value
        snapshot = loaded
    }
}
