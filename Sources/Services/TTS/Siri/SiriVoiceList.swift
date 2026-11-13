import AVFoundation
import Foundation
import Observation

/// Giọng **Siri tiếng Việt** cho hàng "Giọng đọc" của Cài đặt TTS và sheet chọn giọng Siri (chuyển từ
/// `TTSSettingsView.loadSystemVoices`). Đọc **ngoài main** (1.3.713): `speechVoices()` dò kho giọng của hệ thống, chậm —
/// gọi thẳng trong `onAppear` là chặn hoạt cảnh mở sheet. Danh sách trống một nhịp rồi mới có.
@MainActor
@Observable
final class SiriVoiceList {
    static let shared = SiriVoiceList()

    /// Bản chụp một giọng (`AVSpeechSynthesisVoice` không đi qua ranh giới luồng).
    struct Item: Identifiable, Hashable, Sendable {
        /// `AVSpeechSynthesisVoice.identifier` — giá trị `selectedVoice` của trình đọc Siri.
        let id: String
        let name: String
        let qualityTitle: String

        var detail: String { "Tiếng Việt · \(qualityTitle)" }
    }

    private(set) var voices: [Item] = []
    private(set) var hasLoaded = false
    @ObservationIgnored private var loadTask: Task<Void, Never>?

    private init() {}

    func voice(id: String) -> Item? {
        voices.first { $0.id == id }
    }

    /// Đọc lại danh sách (giọng mới tải trong Cài đặt iOS hiện ra ở lần mở sau). Trình đọc là Siri mà chưa có giọng ⇒ chọn
    /// sẵn giọng đầu tiên, như `loadSystemVoices` cũ.
    func reload() {
        guard loadTask == nil else { return }
        loadTask = Task { [weak self] in
            let items = await Task.detached(priority: .userInitiated) { SiriVoiceList.readVoices() }.value
            guard let self else { return }
            self.voices = items
            self.hasLoaded = true
            self.loadTask = nil
            let tts = TTSManager.shared
            if tts.tool == "system", tts.selectedVoice.isEmpty, let first = items.first {
                tts.selectedVoice = first.id
            }
        }
    }

    private nonisolated static func readVoices() -> [Item] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("vi") }
            .map { Item(id: $0.identifier, name: $0.name, qualityTitle: qualityTitle($0.quality)) }
    }

    /// "Premium" / "Nâng cao" / "Mặc định".
    nonisolated static func qualityTitle(_ quality: AVSpeechSynthesisVoiceQuality) -> String {
        switch quality {
        case .premium: return "Premium"
        case .enhanced: return "Nâng cao"
        default: return "Mặc định"
        }
    }
}
