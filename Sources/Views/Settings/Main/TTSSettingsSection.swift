import SwiftUI

/// Section "Nghe Truyện (TTS)" của màn Cài Đặt. Tách khỏi `SettingsView` để file đó không phình thêm.
struct TTSSettingsSection: View {
    var body: some View {
        Section(header: Text("Nghe Truyện (TTS) · Chung")) {
            NavigationLink(destination: TTSSettingsView(isPresentedAsSheet: false)) {
                Label("Cài đặt TTS", systemImage: "waveform")
            }
            NavigationLink(destination: TTSReplacementManagerView()) {
                Label("Quản lý thay thế ký tự", systemImage: "pencil.and.outline")
            }
        }
        Section(header: Text("Nghe Truyện (TTS) · NghiTTS")) {
            NavigationLink(destination: TTSModelManagerView()) {
                Label {
                    Text("Quản lý Model")
                } icon: {
                    Image(systemName: "waveform.and.mic").foregroundColor(.white)
                }
            }
            NavigationLink(destination: TTSDictionaryEditView()) {
                Label("Từ điển phiên âm cá nhân", systemImage: "character.book.closed")
            }
            NavigationLink(destination: NghiTTSSettingsView()) {
                Label("Cấu hình tiền xử lý & ngắt nghỉ", systemImage: "slider.horizontal.3")
            }
        }
        // Màn VieNeu đứng riêng: nó là engine thứ hai, không phải tuỳ chọn của NghiTTS/Piper.
        Section(header: Text("Nghe Truyện (TTS) · VieNeu")) {
            NavigationLink(destination: VieNeuTTSTestView()) {
                Label("Cài đặt VieNeu TTS", systemImage: "waveform.badge.plus")
            }
        }
    }
}
