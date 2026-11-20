import Foundation

/// Dữ liệu cho danh sách **từ điển gốc** VietPhrase.dat / Names.dat (thẻ VietPhrase.txt / Name.txt › Sửa —
/// `GlobalBaseDictionaryListView`). Từ điển cỡ triệu mục nên **không** dựng mảng cặp khoá–nghĩa: mở màn dựng **một lần**
/// `BaseDictionaryIndex` ở nền (trang đầu hiện ngay khi đủ, 1.3.1037), nghĩa của hàng tra lúc hàng hiện
/// (`baseMeaning`), tìm kiếm chạy trên chỉ mục đó (`searchUpdates` ⇒ `BaseDictionaryIndexSearch`) và trả kết quả dần.
///
/// "Nghĩa hiệu lực" = từ điển gốc + lớp sửa đổi Chung (`CustomVietPhrase.txt` / `CustomNames.txt`): từ đã sửa lấy nghĩa
/// mới, từ đã xoá (tombstone) ẩn, từ chỉ có ở lớp sửa đổi đứng đầu. Log `📚` / `🔎 [VPList]`.
enum BaseDictionaryBrowser {
    /// Trần số kết quả tìm — dòng tổng ghi "500 kết quả đầu".
    static let searchLimit = 500

    /// Cây đã nạp của từ điển gốc (`nil` = chưa có `.dat` / chưa nạp).
    static func loadedDictionary(isName: Bool) -> FrozenTrieDictionary? {
        let manager = TranslationManager.shared
        return (isName ? manager.namesDict : manager.vietPhraseDict)?.frozen()
    }

    /// Nghĩa trong từ điển gốc của **đúng** khoá này (khớp đủ độ dài), `nil` nếu không có.
    static func baseMeaning(of key: String, in dictionary: FrozenTrieDictionary?) -> String? {
        guard let dictionary, !key.isEmpty,
              let match = dictionary.findLongestMatch(text: key, startIndex: 0),
              match.length == key.utf16.count else { return nil }
        return match.value
    }

    struct SearchResult: Sendable {
        let keys: [String]
        /// Chạm trần `searchLimit` — còn kết quả chưa hiện.
        let isCapped: Bool
        /// `false` = bản chụp giữa chừng, lượt tìm còn đang quét.
        let isComplete: Bool
    }

    /// Dựng chỉ mục ở nền. Không theo huỷ của màn (việc có chặn trên; màn tự bỏ qua nếu đã có chỉ mục). `onFirstPage`
    /// chạy trên main với `firstPageSize` khoá đầu — có thể tới **sau** khi hàm này trả về.
    static func buildIndex(
        of dictionary: FrozenTrieDictionary,
        label: String,
        firstPageSize: Int,
        onFirstPage: @escaping @MainActor ([String]) -> Void
    ) async -> BaseDictionaryIndex {
        await Task.detached(priority: .userInitiated) {
            let started = Date()
            var firstPageMs: Double?
            let index = BaseDictionaryIndex.build(from: dictionary, firstPageSize: firstPageSize) { keys in
                firstPageMs = Date().timeIntervalSince(started) * 1000
                Task { @MainActor in onFirstPage(keys) }
            }
            let totalMs = Date().timeIntervalSince(started) * 1000
            AppLogger.shared.log(
                "📚 [VPList] Dựng chỉ mục \(label): \(index.count) mục (đầu file ghi \(dictionary.wordCount)), "
                    + "\(String(format: "%.0f", totalMs)) ms, trang đầu sau \(String(format: "%.0f", firstPageMs ?? totalMs)) ms"
            )
            return index
        }.value
    }

    /// Số luồng quét nghĩa: 2–3 luồng, chỉ 1 khi TTS offline (NghiTTS / VieNeu) đang đọc — đừng giành CPU của nó.
    @MainActor
    static func meaningSearchWorkers() -> Int {
        let tts = TTSManager.shared
        if tts.isPlaying, TTSManager.isLocalEngine(tts.tool) { return 1 }
        return ProcessInfo.processInfo.activeProcessorCount >= 6 ? 3 : 2
    }

    /// Lượt tìm chạy nền, gửi bản chụp kết quả dần; người nghe thôi (gõ tiếp ⇒ `.task` huỷ) thì huỷ lượt quét.
    static func searchUpdates(
        _ query: String,
        index: BaseDictionaryIndex?,
        custom: [(key: String, value: String)],
        deleted: Set<String>,
        workers: Int,
        label: String
    ) -> AsyncStream<SearchResult> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let task = Task.detached(priority: .userInitiated) {
                BaseDictionaryIndexSearch.run(
                    query, index: index, custom: custom, deleted: deleted, workers: workers, label: label
                ) { continuation.yield($0) }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
