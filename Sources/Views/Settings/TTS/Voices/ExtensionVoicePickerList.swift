import SwiftUI

/// Danh sách giọng của sheet chọn giọng **tiện ích TTS**: một nhóm mang tên tiện ích, giọng do script `voice` của tiện ích
/// trả về (`ExtensionTTSVoiceList` — hàng "Giọng đọc" đã nạp thì dùng lại, chưa thì nạp ở đây), dòng phụ là ngôn ngữ.
/// ▶ tổng hợp câu mẫu bằng đúng script `tts` của tiện ích (`ExtTTSService`, runtime của trình đọc).
struct ExtensionVoicePickerList: View {
    let packageId: String
    /// Chữ ô tìm (chưa chuẩn hoá).
    let query: String

    @ObservedObject private var ttsManager = TTSManager.shared

    private var list: ExtensionTTSVoiceList { .shared }

    private var extensionRecord: Extension? {
        ExtensionLibraryRepository.shared.catalog.first { $0.packageId == packageId }
    }

    var body: some View {
        let title = extensionRecord?.name ?? packageId
        let isCurrent = list.packageId == packageId
        let allVoices = isCurrent ? list.voices : []
        let normalized = VoiceNameSearch.normalize(query)
        let voices = allVoices.filter { VoiceNameSearch.matches($0.name, normalizedQuery: normalized) }
        List {
            Group {
                if !voices.isEmpty {
                    Section(title) {
                        ForEach(voices) { voice in row(voice) }
                    }
                } else if !allVoices.isEmpty {
                    TTSVoiceNoMatchSection(query: query)
                } else if !isCurrent || list.isLoading || !list.hasLoaded {
                    Section(title) {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Đang tải giọng…")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                    }
                } else {
                    Section(title) {
                        Text("Tiện ích không trả về giọng nào.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .glassSheetRows()
        }
        .onAppear {
            // Hàng "Giọng đọc" đã nạp danh sách của tiện ích này ⇒ dùng lại, không chạy script lần nữa.
            guard list.packageId != packageId || (!list.hasLoaded && !list.isLoading) else { return }
            list.load(packageId: packageId)
        }
    }

    private func row(_ voice: ExtensionTTSVoiceList.Item) -> some View {
        let key = "ext:\(packageId):\(voice.id)"
        return TTSVoiceListRow(
            name: voice.name,
            detail: voice.language,
            isReady: true,
            isSelected: ttsManager.tool == packageId && ttsManager.selectedVoice == voice.id,
            primary: TTSVoicePreviewPlayer.shared.isActive(key) ? .stop : .play,
            badge: .online,
            onPrimary: { primaryTapped(voice, key: key) },
            onSelect: { select(voice) }
        )
    }

    private func primaryTapped(_ voice: ExtensionTTSVoiceList.Item, key: String) {
        guard let ext = extensionRecord else {
            ToastManager.shared.show(message: "Không tìm thấy tiện ích \(packageId).", type: .error)
            return
        }
        TTSVoicePreviewToggle.toggle(
            key: key,
            request: .ext(localPath: ext.localPath, configJson: ext.configJson, voiceId: voice.id)
        )
    }

    /// Sheet chỉ mở khi trình đọc là tiện ích này; chặn thêm để không ghi giọng vào khoá của engine khác.
    private func select(_ voice: ExtensionTTSVoiceList.Item) {
        guard ttsManager.tool == packageId, ttsManager.selectedVoice != voice.id else { return }
        ttsManager.selectedVoice = voice.id
    }
}
