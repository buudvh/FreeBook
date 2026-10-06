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
        // Kokoro cũng là màn **đo**, không phải engine đã nối vào Picker "Trình đọc": tiêu chí go/no-go là
        // RTF < 1,0 **và** RAM đỉnh thấp hơn VieNeu. Nó dùng chung `sea_g2p.bin` với VieNeu nên **cần model
        // VieNeu có trên máy** — thiếu thì nút tải báo đúng câu đó.
        Section(header: Text("Nghe Truyện (TTS) · Kokoro (thử nghiệm)")) {
            NavigationLink(destination: KokoroTTSTestView()) {
                Label("Thử Kokoro", systemImage: "waveform.badge.mic")
            }
        }
    }
}
