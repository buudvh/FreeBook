import SwiftUI

/// Danh sách giọng của sheet chọn giọng **Google Cloud TTS**: "Giọng nữ" / "Giọng nam" từ `GoogleVoice.allVoices`, dòng phụ
/// là mô tả giọng. ▶ tổng hợp câu mẫu qua `GoogleTTSService` (cần API key — thiếu thì toast, không gọi mạng).
struct GoogleVoicePickerList: View {
    /// Chữ ô tìm (chưa chuẩn hoá).
    let query: String

    @ObservedObject private var ttsManager = TTSManager.shared

    var body: some View {
        let normalized = VoiceNameSearch.normalize(query)
        let voices = GoogleVoice.allVoices.filter { VoiceNameSearch.matches($0.name, normalizedQuery: normalized) }
        let female = voices.filter { $0.gender == "Nữ" }
        let male = voices.filter { $0.gender != "Nữ" }
        List {
            Group {
                if !female.isEmpty {
                    Section("Giọng nữ") {
                        ForEach(female) { voice in row(voice) }
                    }
                }
                if !male.isEmpty {
                    Section("Giọng nam") {
                        ForEach(male) { voice in row(voice) }
                    }
                }
                if voices.isEmpty {
                    TTSVoiceNoMatchSection(query: query)
                }
            }
            .glassSheetRows()
        }
    }

    private func row(_ voice: GoogleVoice) -> some View {
        let key = "google:\(voice.id)"
        return TTSVoiceListRow(
            name: voice.name,
            detail: voice.description,
            isReady: true,
            isSelected: ttsManager.tool == "google" && ttsManager.selectedVoice == voice.id,
            primary: TTSVoicePreviewPlayer.shared.isActive(key) ? .stop : .play,
            badge: .online,
            onPrimary: { primaryTapped(voice, key: key) },
            onSelect: { select(voice) }
        )
    }

    private func primaryTapped(_ voice: GoogleVoice, key: String) {
        let preview = TTSVoicePreviewPlayer.shared
        guard preview.isActive(key) || GoogleTTSService.shared.hasApiKey else {
            ToastManager.shared.show(message: "Chưa có API key Google TTS. Nhập key ở Cài đặt TTS rồi thử lại.", type: .info)
            return
        }
        TTSVoicePreviewToggle.toggle(key: key, request: .google(voiceId: voice.id))
    }

    /// Sheet chỉ mở khi trình đọc là Google; chặn thêm để không ghi giọng Google vào khoá của engine khác.
    private func select(_ voice: GoogleVoice) {
        guard ttsManager.tool == "google", ttsManager.selectedVoice != voice.id else { return }
        ttsManager.selectedVoice = voice.id
    }
}
