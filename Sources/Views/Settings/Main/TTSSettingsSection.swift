import SwiftUI

/// Section "Nghe Truyện (TTS)" của màn Cài Đặt. Tách khỏi `SettingsView` để file đó không phình thêm.
struct TTSSettingsSection: View {
    var body: some View {
        Section(header: Text("Nghe Truyện (TTS)")) {
            NavigationLink(destination: TTSSettingsView(isPresentedAsSheet: false)) {
                Label("Cài đặt TTS", systemImage: "waveform")
            }
            NavigationLink(destination: TTSModelManagerView()) {
                Label("Quản lý Model", systemImage: "waveform.and.mic")
            }
            NavigationLink(destination: VieNeuModelManagerView()) {
                Label("Model VieNeu-TTS (offline)", systemImage: "cpu")
            }
            NavigationLink(destination: TTSDictionaryEditView()) {
                Label("Từ điển phiên âm cá nhân", systemImage: "character.book.closed")
            }
            NavigationLink(destination: TTSReplacementManagerView()) {
                Label("Quản lý thay thế ký tự", systemImage: "pencil.and.outline")
            }
            NavigationLink(destination: NghiTTSSettingsView()) {
                Label("Cấu hình tiền xử lý & ngắt nghỉ", systemImage: "slider.horizontal.3")
            }
        }
    }
}
