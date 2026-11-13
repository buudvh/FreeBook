import Foundation

/// **Thư viện phiên âm NghiTTS** (`acronyms.plist` + `non-vietnamese-words.plist`, `NghiTTSClient.downloadDictionaries`):
/// tải **kèm** lượt tải giọng từ sheet chọn giọng NghiTTS khi máy chưa có — người dùng không phải tải riêng ở từ điển.
/// Một lượt mỗi lúc (`tasks`), kết quả báo qua `lastNotice` như các đích khác; không huỷ được (như giọng NghiTTS).
extension ModelDownloadCenter {
    /// Khoá riêng — **không** bắt đầu bằng `Target.nghiPrefix` để không trùng khoá với một giọng.
    static let nghiDictionaryTarget = "nghiDictionary"

    /// Bắt đầu tải thư viện phiên âm nếu máy chưa có và chưa có lượt nào đang chạy.
    func startNghiDictionaryDownloadIfMissing() {
        let id = Self.nghiDictionaryTarget
        guard tasks[id] == nil, let store = try? ModelStore() else { return }
        let marker = store.rootURL.appendingPathComponent(NghiVoiceDirectory.dictionaryMarker)
        guard !FileManager.default.fileExists(atPath: marker.path) else { return }
        // Chưa có client ⇒ lượt tải giọng đi cùng sẽ báo lỗi "hãy mở lại app"; đừng báo hai lần.
        guard TTSManager.shared.nghiTTSClient != nil else { return }

        let title = "Thư viện phiên âm NghiTTS"
        upsert(Entry(id: id, title: title, message: "Bắt đầu tải…"))
        tasks[id] = Task { [weak self] in
            var failure: String?
            if let client = TTSManager.shared.nghiTTSClient {
                do {
                    try await client.downloadDictionaries()
                } catch {
                    failure = error.localizedDescription
                }
            } else {
                failure = "Chưa sẵn sàng tải thư viện phiên âm — hãy mở lại app"
            }
            guard let self else { return }
            self.finish(id: id, title: title, failure: failure)
            NghiVoiceDirectory.shared.reload()
        }
    }
}
