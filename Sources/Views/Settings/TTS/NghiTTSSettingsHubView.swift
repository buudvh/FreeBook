import SwiftUI

/// Hub **"Cài đặt NghiTTS"** — một chỗ cho mọi thứ thuộc engine NghiTTS (Piper): hàng "Giọng đọc NghiTTS" (mở sheet chọn
/// giọng chung — tải / thử / xoá / nhập giọng ở đó), thông tin model (engine, giọng đã tải, thư viện phiên âm), danh sách
/// giọng đã tải kèm dung lượng, nút "Xoá tất cả giọng NghiTTS" (cuối mục Model, hỏi lại) và lối vào từ điển phiên âm +
/// cấu hình tiền xử lý.
///
/// Dung lượng đọc đĩa ở nền (`ModelSnapshot`, `.task` + `Task.detached`), không trong `body`; `.task` chạy lại mỗi lần
/// màn hiện ra, và đọc lại khi sheet chọn giọng đóng ⇒ số liệu theo kịp lượt tải / xoá.
struct NghiTTSSettingsHubView: View {
    @State var snapshot: ModelSnapshot?
    /// Sheet chọn giọng NghiTTS (`.nghi` = đang mở).
    @State var voicePicker: TTSVoiceEngine?
    /// Tăng khi sheet chọn giọng đóng ⇒ `body` đọc lại giọng đang dùng (không observe `TTSManager`).
    @State var selectionToken = 0
    /// Hộp xác nhận "Xoá tất cả giọng NghiTTS" / đang xoá (vòng xoay trên hàng). `internal` vì hàng nằm ở `+Sections`.
    @State var isWipeConfirmPresented = false
    @State var isWiping = false

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
        .confirmationDialog("Xoá tất cả giọng NghiTTS?", isPresented: $isWipeConfirmPresented, titleVisibility: .visible) {
            Button("Xoá tất cả", role: .destructive) { commitWipe() }
            Button("Huỷ", role: .cancel) {}
        } message: {
            let count = snapshot?.voices.count ?? 0
            let size = Self.size(snapshot?.voiceBytes ?? 0)
            Text("Xoá \(count) giọng (\(size)), kể cả giọng nhập từ file. Thư viện phiên âm giữ lại; tải lại giọng ở sheet chọn giọng.")
        }
    }

    /// Xoá mọi giọng (đã xác nhận): dừng câu thử (Piper chỉ giữ một session), service tự dừng trình đọc NghiTTS đang có
    /// phiên; View báo kết quả bằng toast rồi đọc lại số liệu.
    private func commitWipe() {
        guard !isWiping else { return }
        isWiping = true
        TTSVoicePreviewPlayer.shared.stop()
        Task {
            do {
                let removed = try await NghiVoiceDirectory.shared.deleteAll()
                selectionToken += 1
                ToastManager.shared.show(message: "Đã xoá \(removed) giọng NghiTTS.", type: .success)
            } catch {
                ToastManager.shared.show(message: "Xoá giọng NghiTTS thất bại: \(error.localizedDescription)", type: .error)
            }
            await reloadSnapshot()
            isWiping = false
        }
    }

    private func reloadSnapshot() async {
        let loaded = await Task.detached(priority: .userInitiated) {
            Self.loadModelSnapshot()
        }.value
        snapshot = loaded
    }
}
