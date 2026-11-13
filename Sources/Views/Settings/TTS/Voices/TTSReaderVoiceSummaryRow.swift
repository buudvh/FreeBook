import SwiftUI

/// Hàng **"Giọng đọc"** của Cài đặt TTS khi trình đọc là Siri / NghiTTS / Google / tiện ích (VieNeu có
/// `VieNeuVoiceSummaryRow`): tên giọng trình đọc đang dùng, dòng phụ theo trình đọc, badge Nhẹ / Online. Bấm ⇒ sheet chọn
/// giọng (`onTap`).
///
/// - Siri: "Tiếng Việt · <chất lượng>" (`SiriVoiceList`). NghiTTS: dung lượng giọng đã tải, chưa tải ⇒ dòng cam
///   (`NghiVoiceDirectory`). Google: mô tả giọng. Tiện ích: ngôn ngữ của giọng (`ExtensionTTSVoiceList`).
/// - Hàng tự nạp danh sách giọng của trình đọc khi hiện ra / khi đổi trình đọc (`.task(id:)`) — trước đây
///   `TTSSettingsView.onAppear` làm việc này.
struct TTSReaderVoiceSummaryRow: View {
    let engine: TTSVoiceEngine
    let onTap: () -> Void

    @ObservedObject private var ttsManager = TTSManager.shared

    var body: some View {
        let summary = currentSummary
        TTSVoiceSummaryRow(
            name: summary.name,
            detail: summary.detail,
            isMissing: summary.isMissing,
            badge: engine.badge,
            onTap: onTap
        )
        .task(id: engine) { loadVoices() }
    }

    private func loadVoices() {
        switch engine {
        case .siri: SiriVoiceList.shared.reload()
        case .nghi: NghiVoiceDirectory.shared.reload()
        case .google: break
        case .ext(let packageId): ExtensionTTSVoiceList.shared.load(packageId: packageId)
        }
    }

    private var currentSummary: (name: String, detail: String?, isMissing: Bool) {
        let selected = ttsManager.selectedVoice
        switch engine {
        case .siri:
            let list = SiriVoiceList.shared
            if let voice = list.voice(id: selected) {
                return (voice.name, voice.detail, false)
            }
            return (list.hasLoaded ? "Chưa chọn giọng" : "Siri", nil, false)
        case .nghi:
            let directory = NghiVoiceDirectory.shared
            let name = directory.readerVoiceName(tool: ttsManager.tool, selectedVoice: selected)
            guard !name.isEmpty else { return ("Chưa chọn giọng", nil, false) }
            let voice = directory.voice(named: name)
            if let bytes = directory.bytes(of: voice) {
                return (voice.name, NghiVoiceDirectory.sizeText(bytes), false)
            }
            // Lần vẽ đầu (trước khi đọc đĩa xong) chưa biết đã tải hay chưa ⇒ chưa hiện cảnh báo.
            return (voice.name, nil, directory.hasLoaded)
        case .google:
            let voice = GoogleVoice.allVoices.first { $0.id == selected }
            return (voice?.name ?? selected, voice?.description, false)
        case .ext(let packageId):
            let list = ExtensionTTSVoiceList.shared
            let isCurrent = list.packageId == packageId
            if isCurrent, let voice = list.voice(id: selected) {
                return (voice.name, voice.language.isEmpty ? nil : voice.language, false)
            }
            let loading = !isCurrent || list.isLoading
            return (selected.isEmpty ? "Chưa chọn giọng" : selected, loading ? "Đang tải giọng…" : nil, false)
        }
    }
}
