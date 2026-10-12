import SwiftUI

/// Màn "Nghe truyện (TTS)" (Cài đặt → Đọc & Nghe). Chuyển nguyên 3 nhóm từ `TTSSettingsSection` cũ (1.3.520);
/// chỉ rút gọn tiêu đề nhóm vì tiêu đề màn đã là TTS.
struct TTSSettingsHubView: View {
    var body: some View {
        Form {
            Section(header: Text("Chung")) {
                NavigationLink(destination: TTSSettingsView(isPresentedAsSheet: false)) {
                    Label("Cài đặt TTS", systemImage: "waveform")
                }
                NavigationLink(destination: TTSReplacementManagerView()) {
                    Label("Quản lý thay thế ký tự", systemImage: "pencil.and.outline")
                }
            }
            Section(header: Text("NghiTTS")) {
                // Một lối vào duy nhất: hub gom cả 3 mục quản lý **và** phần thử giọng (trước đây 3 nav rời ở
                // đây cộng thêm 1 nav nữa nằm sâu trong "Cấu hình NghiTTS").
                NavigationLink(destination: NghiTTSSettingsHubView()) {
                    Label("Cài đặt NghiTTS", systemImage: "waveform.and.mic")
                }
            }
            // Màn VieNeu đứng riêng: nó là engine thứ hai, không phải tuỳ chọn của NghiTTS/Piper.
            Section(header: Text("VieNeu")) {
                NavigationLink(destination: VieNeuTTSTestView()) {
                    Label("Cài đặt VieNeu TTS", systemImage: "waveform.badge.plus")
                }
            }
        }
        .navigationTitle("Nghe truyện (TTS)")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Tên hiển thị của engine theo giá trị `ttsTool` (khoá UserDefaults `TTSManager` ghi): dùng cho chữ phụ của
    /// dòng "Nghe truyện (TTS)" ở tab Cài đặt và dòng "TTS" của màn Theo dõi nhiệt.
    static func engineName(for tool: String) -> String {
        switch tool {
        case "google": return "Google"
        case "nghitts": return "NghiTTS"
        case "vieneu": return "VieNeu"
        case "system": return "Siri"
        default: return "Extension"
        }
    }
}
