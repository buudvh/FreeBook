import Foundation
import Observation

/// Nguồn sự thật **danh sách giọng VieNeu Turbo người dùng tự tạo** cho UI (1.3.891). View đọc `voices` trong `body`;
/// tạo giọng đi qua `VieNeuTurboVoiceCloneCoordinator` (xong thì gọi `reload()` ở đây), đổi tên / xoá gọi thẳng.
///
/// API cho màn chọn giọng / tạo giọng (làm sau theo mockup):
/// - `voices`, `voice(id:)`, `reload()`, `loadError`
/// - `rename(id:to:)`, `delete(id:)`
/// - `voiceFiles(id:)` — cặp `ref_codes.txt` + `speaker.emb.txt` để chia sẻ / so; `sampleURL(id:)` — mẫu gốc nếu giữ
///
/// Id giọng tự tạo dùng thẳng làm giọng của trình đọc Turbo (`VieNeuVoiceSelection` "turbo:custom_…"):
/// `VieNeuTurboTTSService` nhận id `custom_…` khi cặp file còn trên máy, đã xoá thì tự về giọng mặc định.
@MainActor
@Observable
final class VieNeuTurboCustomVoiceRepository {
    static let shared = VieNeuTurboCustomVoiceRepository()

    private(set) var voices: [VieNeuTurboCustomVoiceStore.Record] = []
    /// Lỗi đọc index gần nhất (file hỏng) — `nil` khi đọc được (kể cả khi chưa có giọng nào).
    private(set) var loadError: String?

    let store: VieNeuTurboCustomVoiceStore?

    private init() {
        store = (try? VieNeuTurboModelStore()).map { VieNeuTurboCustomVoiceStore(modelStore: $0) }
        store?.removeLeftoverStaging()
        reload()
    }

    func reload() {
        guard let store else {
            voices = []
            loadError = "Không dựng được thư mục VieNeu Turbo (Application Support không ghi được)."
            return
        }
        do {
            voices = try store.load()
            loadError = nil
        } catch {
            voices = []
            loadError = error.localizedDescription
            AppLogger.shared.log("❌ [VieNeuTurboClone] Đọc danh sách giọng tự tạo lỗi: \(error.localizedDescription)")
        }
    }

    func voice(id: String) -> VieNeuTurboCustomVoiceStore.Record? {
        voices.first { $0.id == id }
    }

    func rename(id: String, to name: String) throws {
        guard let store else { throw VieNeuTurboCustomVoiceStore.StoreError.notFound(id) }
        try store.rename(id: id, to: name)
        reload()
    }

    /// Xoá giọng + file của nó. Trình đọc đang dùng giọng này thì đoạn kế tự về giọng mặc định
    /// (`VieNeuTurboTTSService.resolveVoiceId`).
    func delete(id: String) throws {
        guard let store else { throw VieNeuTurboCustomVoiceStore.StoreError.notFound(id) }
        try store.delete(id: id)
        AppLogger.shared.log("🎙️ [VieNeuTurboClone] Đã xoá giọng tự tạo \(id)")
        reload()
    }

    /// Cặp file của giọng (chỉ khi cả hai còn trên đĩa).
    func voiceFiles(id: String) -> (referenceCodes: URL, speakerEmbedding: URL)? {
        guard let modelStore = try? VieNeuTurboModelStore(), modelStore.hasVoice(voiceId: id) else { return nil }
        return (modelStore.referenceCodesURL(voiceId: id), modelStore.speakerEmbeddingURL(voiceId: id))
    }

    func sampleURL(id: String) -> URL? {
        guard let store, let record = voice(id: id) else { return nil }
        return store.sampleURL(for: record)
    }
}
