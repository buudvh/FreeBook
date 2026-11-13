import SwiftUI

/// Danh sách giọng của sheet chọn giọng **Siri**: nhóm "Giọng trên máy" = giọng tiếng Việt của iOS (`SiriVoiceList`, đọc
/// ngoài main). ▶ đọc câu mẫu bằng `AVSpeechSynthesizer` với giọng đó; chạm hàng = chọn giọng cho trình đọc Siri.
struct SiriVoicePickerList: View {
    /// Chữ ô tìm (chưa chuẩn hoá).
    let query: String

    @ObservedObject private var ttsManager = TTSManager.shared

    private var list: SiriVoiceList { .shared }

    var body: some View {
        let normalized = VoiceNameSearch.normalize(query)
        let voices = list.voices.filter { VoiceNameSearch.matches($0.name, normalizedQuery: normalized) }
        List {
            Group {
                if !voices.isEmpty {
                    Section("Giọng trên máy") {
                        ForEach(voices) { voice in
                            row(voice)
                        }
                    }
                } else if !normalized.isEmpty, !list.voices.isEmpty {
                    TTSVoiceNoMatchSection(query: query)
                } else if list.hasLoaded {
                    Section {
                        Text("Máy chưa có giọng Siri tiếng Việt nào.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                } else {
                    Section {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Đang đọc danh sách giọng…")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .glassSheetRows()
        }
        .onAppear { list.reload() }
    }

    private func row(_ voice: SiriVoiceList.Item) -> some View {
        let key = "siri:\(voice.id)"
        return TTSVoiceListRow(
            name: voice.name,
            detail: voice.detail,
            isReady: true,
            isSelected: ttsManager.tool == "system" && ttsManager.selectedVoice == voice.id,
            primary: TTSVoicePreviewPlayer.shared.isActive(key) ? .stop : .play,
            badge: .light,
            onPrimary: { TTSVoicePreviewToggle.toggle(key: key, request: .siri(identifier: voice.id)) },
            onSelect: { select(voice) }
        )
    }

    /// Sheet chỉ mở khi trình đọc là Siri; chặn thêm để không ghi giọng Siri vào khoá của engine khác.
    private func select(_ voice: SiriVoiceList.Item) {
        guard ttsManager.tool == "system", ttsManager.selectedVoice != voice.id else { return }
        ttsManager.selectedVoice = voice.id
    }
}
