import Foundation
import Observation

/// **Giọng NghiTTS** (Piper) cho hàng "Giọng đọc" của Cài đặt TTS, sheet chọn giọng NghiTTS và trang Cài đặt NghiTTS:
/// danh mục `NghiTTSClient.fallbackVietnameseVoices` + giọng tự nhập (id dưới máy không thuộc danh mục), kèm dung lượng
/// giọng đã tải và trạng thái thư viện phiên âm. Đọc đĩa **ngoài main** (`reload()`); View chỉ đọc bản chụp.
///
/// Thay phần danh sách của màn "Quản lý model" cũ (`TTSModelManagerView`, bỏ ở lượt sheet chọn giọng).
@MainActor
@Observable
final class NghiVoiceDirectory {
    static let shared = NghiVoiceDirectory()

    /// 4 giọng "đặc sắc" — cùng danh sách với `NghiTTSClient.getAllVoices`.
    nonisolated static let featuredNames = ["Ngọc Huyền (mới)", "Mai Phương", "Duy Onyx (mới)", "Ngọc Ngạn"]
    /// Khoá giọng NghiTTS đã lưu (`TTSManager.persistVoice` khi trình đọc là NghiTTS).
    nonisolated static let voiceDefaultsKey = "nghittsVoice"
    /// File đánh dấu "đã tải thư viện phiên âm" trong `ModelStore.rootURL` (tải cùng `acronyms.plist`).
    nonisolated static let dictionaryMarker = "non-vietnamese-words.plist"

    /// Số liệu đĩa: giọng đã tải đủ `.onnx` + `.onnx.json` (id ⇒ byte) và thư viện phiên âm.
    struct Snapshot: Sendable {
        var bytesById: [String: Int64] = [:]
        var hasDictionary = false
    }

    private(set) var snapshot = Snapshot()
    private(set) var hasLoaded = false
    /// Tăng khi chọn / xoá giọng ⇒ View đọc lại giọng đã lưu ở `UserDefaults` (không quan sát được).
    private(set) var selectionRevision = 0
    @ObservationIgnored private var reloadTask: Task<Void, Never>?
    @ObservationIgnored private var needsAnotherReload = false

    private init() {}

    // MARK: - Danh sách

    var catalog: [Voice] { NghiTTSClient.fallbackVietnameseVoices }

    /// "Giọng đặc sắc" — theo thứ tự danh mục.
    var featured: [Voice] {
        catalog.filter { Self.isFeatured($0) }
    }

    /// "Giọng khác": phần còn lại của danh mục, giọng đã tải lên trước rồi theo tên.
    var others: [Voice] {
        let rest = catalog.filter { !Self.isFeatured($0) }
        let downloaded = rest.filter { isDownloaded($0) }.sorted(by: Self.byName)
        let notDownloaded = rest.filter { !isDownloaded($0) }.sorted(by: Self.byName)
        return downloaded + notDownloaded
    }

    /// "Giọng của tôi": giọng đã có dưới máy mà không thuộc danh mục (tự nhập), tên viết lại từ id.
    var mine: [Voice] {
        let catalogIds = Set(catalog.map(\.id))
        return snapshot.bytesById.keys
            .filter { !catalogIds.contains($0) }
            .map { Voice(id: $0, name: Self.displayName(forLocalId: $0)) }
            .sorted(by: Self.byName)
    }

    func isCatalogVoice(_ voice: Voice) -> Bool {
        catalog.contains { $0.id == voice.id }
    }

    func isDownloaded(_ voice: Voice) -> Bool {
        snapshot.bytesById[voice.id] != nil
    }

    func bytes(of voice: Voice) -> Int64? {
        snapshot.bytesById[voice.id]
    }

    /// Giọng ứng với tên đã lưu: danh mục ⇒ giọng tự nhập ⇒ dựng theo tên (id ASCII như `PiperTTSService`).
    func voice(named name: String) -> Voice {
        if let match = catalog.first(where: { Self.sameName($0.name, name) }) { return match }
        if let match = mine.first(where: { Self.sameName($0.name, name) }) { return match }
        return Voice(name: name)
    }

    /// Tên giọng NghiTTS của trình đọc: `selectedVoice` khi trình đọc là NghiTTS, không thì giá trị đã lưu `nghittsVoice`
    /// (thiếu ⇒ giọng mặc định, như `TTSManager.loadParamsForCurrentTool`).
    func readerVoiceName(tool: String, selectedVoice: String) -> String {
        _ = selectionRevision
        if tool == "nghitts" { return selectedVoice }
        return UserDefaults.standard.string(forKey: Self.voiceDefaultsKey) ?? NghiTTSClient.defaultVietnameseVoice.name
    }

    // MARK: - Hành động

    /// Chọn giọng (theo **tên**, như picker cũ). Trình đọc đang là NghiTTS ⇒ gán `selectedVoice` (tự lưu qua
    /// `persistVoice`); trình đọc khác ⇒ chỉ ghi `nghittsVoice` — gán `selectedVoice` lúc đó là ghi đè giọng của engine kia.
    func select(_ voice: Voice) {
        let tts = TTSManager.shared
        if tts.tool == "nghitts" {
            if tts.selectedVoice != voice.name { tts.selectedVoice = voice.name }
        } else {
            UserDefaults.standard.set(voice.name, forKey: Self.voiceDefaultsKey)
        }
        selectionRevision += 1
    }

    /// Tải giọng; máy chưa có thư viện phiên âm thì tải luôn (lượt riêng của `ModelDownloadCenter`, tự đọc lại khi xong).
    /// Lượt giọng xong (hay lỗi) ⇒ đọc lại đĩa — kể cả khi sheet đã đóng hoặc còn lượt tải khác đang chạy.
    func startDownload(_ voice: Voice) {
        let center = ModelDownloadCenter.shared
        center.startNghiDictionaryDownloadIfMissing()
        center.startNghiVoiceDownloads([voice])
        let target = ModelDownloadCenter.Target.nghiVoice(voice.id)
        Task { [weak self] in
            _ = await ModelDownloadCenter.shared.waitForJob(id: target)
            self?.reload()
        }
    }

    /// Xoá file model của giọng (như "Xóa" của màn quản lý model cũ). Giọng đang chọn của trình đọc NghiTTS ⇒ bỏ chọn.
    func delete(_ voice: Voice) throws {
        let tts = TTSManager.shared
        // Xoá đúng giọng trình đọc đang dùng (kể cả đang tạm dừng) ⇒ dừng phiên trước, kẻo đọc tiếp nạp lại file vừa xoá rồi lỗi.
        if tts.tool == "nghitts", Self.sameName(tts.selectedVoice, voice.name), tts.isPlaying || tts.showFloatingWidget {
            AppLogger.shared.log("⏹️ [NghiTTS] Dừng TTS trước khi xoá giọng đang đọc")
            tts.stop()
        }
        try ModelStore().deleteModel(for: voice.id)
        if tts.tool == "nghitts", Self.sameName(tts.selectedVoice, voice.name) {
            tts.selectedVoice = ""
        }
        selectionRevision += 1
        reload()
    }

    /// "Xoá tất cả giọng NghiTTS" (trang Cài đặt NghiTTS): xoá file model của **mọi** giọng trên máy — danh mục lẫn tự nhập,
    /// lấy id mới từ đĩa chứ không từ bản chụp. Thư viện phiên âm giữ lại. Trình đọc NghiTTS đang có phiên ⇒ dừng trước;
    /// trình đọc là NghiTTS ⇒ bỏ chọn giọng (như `delete`). Lượt tải đang chạy ghi `.partial` rồi mới đổi tên nên không bị
    /// xoá dở. Trả số giọng đã xoá; lỗi giữa chừng ⇒ vẫn đọc lại đĩa rồi ném lỗi.
    func deleteAll() async throws -> Int {
        let tts = TTSManager.shared
        if tts.tool == "nghitts", tts.isPlaying || tts.showFloatingWidget {
            AppLogger.shared.log("⏹️ [NghiTTS] Dừng TTS trước khi xoá tất cả giọng")
            tts.stop()
        }
        let outcome = await Task.detached(priority: .userInitiated) { () -> Result<Int, Error> in
            Result {
                let store = try ModelStore()
                let ids = store.getLocalVoiceIDs()
                for id in ids {
                    try store.deleteModel(for: id)
                }
                return ids.count
            }
        }.value
        if case .success = outcome, tts.tool == "nghitts" {
            tts.selectedVoice = ""
        }
        selectionRevision += 1
        reload()
        let removed = try outcome.get()
        AppLogger.shared.log("🗑️ [NghiTTS] Đã xoá tất cả \(removed) giọng")
        return removed
    }

    /// Đọc lại đĩa ngoài main. Gọi chồng lúc đang đọc ⇒ đọc thêm một lượt sau khi lượt đang chạy xong.
    func reload() {
        guard reloadTask == nil else {
            needsAnotherReload = true
            return
        }
        reloadTask = Task { [weak self] in
            let loaded = await Task.detached(priority: .userInitiated) { NghiVoiceDirectory.readSnapshot() }.value
            guard let self else { return }
            self.snapshot = loaded
            self.hasLoaded = true
            self.reloadTask = nil
            if self.needsAnotherReload {
                self.needsAnotherReload = false
                self.reload()
            }
        }
    }

    // MARK: - Tiện ích

    nonisolated static func sameName(_ lhs: String, _ rhs: String) -> Bool {
        lhs.precomposedStringWithCanonicalMapping == rhs.precomposedStringWithCanonicalMapping
    }

    /// Dung lượng giọng đã tải, "61 MB" — MB nhị phân như màn quản lý model cũ (một giọng Piper medium ~60–61 MiB).
    nonisolated static func sizeText(_ bytes: Int64) -> String {
        String(format: "%.0f MB", Double(bytes) / 1_048_576)
    }

    /// Tên hiển thị của giọng tự nhập — cùng cách viết lại với `NghiTTSClient.getAllVoices`.
    nonisolated static func displayName(forLocalId id: String) -> String {
        id.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private nonisolated static func isFeatured(_ voice: Voice) -> Bool {
        featuredNames.contains { sameName($0, voice.name) }
    }

    private nonisolated static func byName(_ lhs: Voice, _ rhs: Voice) -> Bool {
        lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }

    private nonisolated static func readSnapshot() -> Snapshot {
        guard let store = try? ModelStore() else { return Snapshot() }
        var result = Snapshot()
        for id in store.getLocalVoiceIDs() {
            result.bytesById[id] = store.bytesForVoice(id)
        }
        result.hasDictionary = FileManager.default.fileExists(
            atPath: store.rootURL.appendingPathComponent(dictionaryMarker).path
        )
        return result
    }
}
