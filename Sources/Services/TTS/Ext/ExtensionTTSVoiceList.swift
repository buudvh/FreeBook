import Foundation
import Observation

/// Giọng của **tiện ích TTS** đang chọn cho hàng "Giọng đọc" của Cài đặt TTS và sheet chọn giọng tiện ích (chuyển từ
/// `TTSSettingsView.loadExtensionVoices`): chạy script `voice` của tiện ích (`ExtensionManager.ttsVoices`) rồi giữ bản chụp
/// của **một** tiện ích. Giọng thiếu `id` bị bỏ, `id` trùng chỉ giữ lần đầu.
@MainActor
@Observable
final class ExtensionTTSVoiceList {
    static let shared = ExtensionTTSVoiceList()

    struct Item: Identifiable, Hashable, Sendable {
        /// Giá trị `selectedVoice` của trình đọc.
        let id: String
        let name: String
        let language: String
    }

    /// Tiện ích của danh sách hiện tại.
    private(set) var packageId = ""
    private(set) var voices: [Item] = []
    private(set) var isLoading = false
    /// Đã nạp xong (thành công hay lỗi) ít nhất một lần cho `packageId`.
    private(set) var hasLoaded = false
    @ObservationIgnored private var loadTask: Task<Void, Never>?

    private init() {}

    func voice(id: String) -> Item? {
        voices.first { $0.id == id }
    }

    /// Nạp giọng của tiện ích `packageId` — chạy lại script mỗi lần gọi (như mỗi lần mở Cài đặt TTS trước đây). Trình đọc
    /// đang là tiện ích này mà giọng đã chọn không có trong danh sách ⇒ chọn giọng đầu tiên, như trước.
    func load(packageId: String) {
        loadTask?.cancel()
        loadTask = nil
        guard let ext = ExtensionLibraryRepository.shared.catalog.first(where: { $0.packageId == packageId }) else {
            // Tiện ích không còn trong thư viện ⇒ danh sách rỗng (không treo ở "Đang tải giọng…").
            self.packageId = packageId
            voices = []
            isLoading = false
            hasLoaded = true
            return
        }
        if self.packageId != packageId {
            voices = []
            hasLoaded = false
        }
        self.packageId = packageId
        isLoading = true
        let localPath = ext.localPath
        let downloadUrl = ext.downloadUrl
        let configJson = ext.configJson
        loadTask = Task { [weak self] in
            var raw: [[String: String]] = []
            do {
                raw = try await ExtensionManager.shared.ttsVoices(
                    localPath: localPath, downloadUrl: downloadUrl, configJson: configJson
                )
            } catch {
                AppLogger.shared.log("❌ [ExtTTSVoices] Không lấy được giọng của \(packageId): \(error.localizedDescription)")
            }
            guard let self, !Task.isCancelled, self.packageId == packageId else { return }
            self.voices = Self.items(from: raw)
            self.isLoading = false
            self.hasLoaded = true
            self.loadTask = nil
            let tts = TTSManager.shared
            if tts.tool == packageId, !self.voices.contains(where: { $0.id == tts.selectedVoice }), let first = self.voices.first {
                tts.selectedVoice = first.id
            }
        }
    }

    private nonisolated static func items(from raw: [[String: String]]) -> [Item] {
        var seen = Set<String>()
        return raw.compactMap { dict in
            guard let id = dict["id"], !id.isEmpty, seen.insert(id).inserted else { return nil }
            let name = dict["name"].flatMap { $0.isEmpty ? nil : $0 } ?? id
            return Item(id: id, name: name, language: dict["language"] ?? "")
        }
    }
}
