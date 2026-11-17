import SwiftUI

/// Các hàng **"Quản lý riêng của trình đọc"** của VieNeu — dùng chung cho Cài đặt TTS (`TTSSettingsView+VieNeu`) và màn
/// Giọng dự phòng (`TTSFallbackVoiceSettingsView`). 1.3.961: trước đó hai màn chép riêng một bản, thêm công tắc VieNeu mới
/// là phải nhớ thêm cả hai nơi.
///
/// Gồm: lối vào trang Cài đặt VieNeu TTS, công tắc từ điển phiên âm + "Phiên âm tiếng Nhật" (hàng chung mọi trình đọc,
/// `TTSJapaneseTransliterationRow`), Picker "Đọc chậm đoạn có
/// tên (Nano)", và từ điển tiếng Nhật (đã tải ⇒ lối vào; chưa tải ⇒ cảnh báo + nút tải). Đặt **bên trong** một `Section`
/// (mỗi view con là một hàng).
struct VieNeuReaderManagementRows: View {
    @ObservedObject var flags: VieNeuJapaneseFlags
    /// Mở từ màn Giọng dự phòng ⇒ trang Cài đặt VieNeu TTS chỉ lưu lựa chọn giọng, không chuyển trình đọc chính.
    var selectsForFallback = false

    /// Đoạn giải thích sau nút "?" của tiêu đề "Quản lý riêng của trình đọc" khi trình đọc là VieNeu.
    static let helpParagraphs: [LocalizedStringKey] = [
        "Nano luôn chạy Cân bằng (8 bước) + 2 luồng, không chờ bận. Turbo luôn 2 luồng trên lõi hiệu năng.",
        TTSJapaneseTransliterationRow.helpParagraph(forTool: TTSJapaneseTransliterationSettings.vieNeuTool),
        VieNeuJapaneseFlags.nameFrameBoostHelp
    ]

    var body: some View {
        NavigationLink(destination: VieNeuTTSSettingsView(selectsForFallback: selectsForFallback)) {
            Label("Cài đặt VieNeu TTS", systemImage: "waveform.badge.plus")
        }

        // Từ điển phiên âm tiếng Nhật (chung Nano và Turbo). Mặc định **TẮT**: VieNeu chỉ gấp macron về ASCII
        // (`danzō` → `danzo`), xem `VieNeuJapanesePreprocessor`.
        Toggle("Áp dụng từ điển phiên âm VieNeu", isOn: $flags.dictionaryEnabled)

        // "Phiên âm tiếng Nhật" — công tắc chung mọi trình đọc, lưu riêng từng trình đọc (1.3.973). Với VieNeu: tên kiểu
        // Nhật viết hoa ("Sasuke") đọc theo âm tiết thay vì theo luật chính tả tiếng Anh — mặc định **BẬT**, chung Nano
        // và Turbo (trước 1.3.973 là "Đọc tên Nhật theo âm tiết"). Xem `VieNeuJapaneseNameReader`.
        TTSJapaneseTransliterationRow(tool: TTSJapaneseTransliterationSettings.vieNeuTool)

        // Nano: đoạn có tên phiên âm theo âm tiết được thêm khung để không nuốt âm tiết ngắn (`VieNeuNameFrameBoost`).
        Picker("Đọc chậm đoạn có tên (Nano)", selection: $flags.nameFrameBoost) {
            ForEach(VieNeuNameFrameBoost.Mode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.menu)

        // Từ điển tiếng Nhật: **đã tải ⇒ lối vào; chưa tải ⇒ cảnh báo + nút tải** — mở một màn trống thì người dùng không
        // biết phải làm gì.
        if flags.dictionaryDownloaded {
            NavigationLink(destination: VieNeuJapaneseDictionaryView()) {
                Label("Từ điển phiên âm tiếng Nhật", systemImage: "character.book.closed")
            }
        } else {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                Text("Chưa tải từ điển tiếng Nhật").font(.subheadline).foregroundColor(.secondary)
            }
            Button(action: downloadJapaneseDictionary) {
                Label("Tải từ điển tiếng Nhật", systemImage: "arrow.down.circle")
            }
        }
    }

    /// Tải từ điển rồi làm mới cờ "đã tải" ⇒ hàng cảnh báo + nút tải đổi thành lối vào ngay.
    private func downloadJapaneseDictionary() {
        Task {
            do {
                try await VieNeuJapaneseDictionary.shared.downloadInitialDictionary()
                flags.refresh()
                ToastManager.shared.show(message: "Tải từ điển tiếng Nhật thành công!", type: .success)
            } catch {
                ToastManager.shared.show(message: "Không thể tải từ điển: \(error.localizedDescription)", type: .error)
            }
        }
    }
}
