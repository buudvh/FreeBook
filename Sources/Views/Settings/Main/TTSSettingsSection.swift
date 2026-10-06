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
            // Một lối vào duy nhất: hub gom cả 3 mục quản lý **và** phần thử giọng (trước đây 3 nav rời ở
            // đây cộng thêm 1 nav nữa nằm sâu trong "Cấu hình NghiTTS").
            NavigationLink(destination: NghiTTSSettingsHubView()) {
                Label("Cài đặt NghiTTS", systemImage: "waveform.and.mic")
            }
        }
        // Màn VieNeu đứng riêng: nó là engine thứ hai, không phải tuỳ chọn của NghiTTS/Piper.
        Section(header: Text("Nghe Truyện (TTS) · VieNeu")) {
            NavigationLink(destination: VieNeuTTSTestView()) {
                Label("Cài đặt VieNeu TTS", systemImage: "waveform.badge.plus")
            }
        }
        // ZeroTTS là **spike khảo sát khả thi**, không phải engine đã nối vào Picker "Trình đọc": màn này
        // tồn tại để đo RTF và RAM đỉnh trên máy thật trước khi quyết định có nối hay không.
        Section(header: Text("Nghe Truyện (TTS) · ZeroTTS (thử nghiệm)")) {
            NavigationLink(destination: ZeroTTSTestView()) {
                Label("Thử ZeroTTS", systemImage: "waveform.badge.exclamationmark")
            }
        }
    }
}
