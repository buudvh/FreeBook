import Foundation

/// Trạng thái **lúc chạy** của giọng dự phòng (1.3.945) — `TTSManager` giữ một bản (`onlineFallback`), chỉ chạm trên main.
///
/// - Bật theo **phiên** TTS (`sessionID`): phiên mới ⇒ coi như đang đọc online, đoạn đầu thử online lại.
/// - `chunkEngines`: đoạn nào có tiếng do giọng dự phòng tạo — để phát đúng tốc độ của engine dự phòng và hiện badge
///   "Dự phòng", kể cả sau khi đã quay lại online (đoạn dự phòng đã nạp trước vẫn phát hết).
/// - `inflight`: lượt tổng hợp dự phòng đang chạy theo đoạn — đoạn đang đọc và lượt nạp trước của cùng đoạn dùng chung một
///   lượt. Không huỷ lượt khi người chờ thôi chờ (người chờ khác có thể vẫn cần); dọn ở `forgetChunks()` (xoá bộ đệm TTS:
///   dừng đọc, đổi cài đặt…) và khi lệch phiên / chương.
@MainActor
final class TTSOnlineFallbackState {
    struct ChunkKey: Hashable {
        let sessionID: UUID
        let chapterIndex: Int
        let index: Int
    }

    /// Chờ trước lượt thử online đầu tiên, rồi gấp đôi mỗi lần vẫn lỗi tới `maxProbeDelay`.
    static let firstProbeDelay: TimeInterval = 15
    static let maxProbeDelay: TimeInterval = 120

    private(set) var activeSessionID: UUID?
    private var chunkEngines: [ChunkKey: TTSOnlineFallbackSettings.Engine] = [:]
    private var inflight: [ChunkKey: Task<Data, Error>] = [:]
    var probeTask: Task<Void, Never>?

    func isActive(session: UUID) -> Bool {
        activeSessionID == session
    }

    func activate(session: UUID) {
        if activeSessionID != session {
            dropStale(session: session)
        }
        activeSessionID = session
    }

    func deactivate() {
        activeSessionID = nil
        probeTask?.cancel()
        probeTask = nil
    }

    // MARK: - Đoạn

    func engine(of key: ChunkKey) -> TTSOnlineFallbackSettings.Engine? {
        chunkEngines[key]
    }

    func markFallback(_ key: ChunkKey, engine: TTSOnlineFallbackSettings.Engine) {
        chunkEngines[key] = engine
    }

    func markOnline(_ key: ChunkKey) {
        chunkEngines.removeValue(forKey: key)
    }

    /// Bộ đệm TTS bị xoá ⇒ tiếng đã nạp không còn: quên đoạn và mọi lượt đang chạy.
    func forgetChunks() {
        chunkEngines.removeAll()
        for task in inflight.values { task.cancel() }
        inflight.removeAll()
    }

    // MARK: - Lượt tổng hợp

    func task(for key: ChunkKey) -> Task<Data, Error>? {
        inflight[key]
    }

    func store(_ task: Task<Data, Error>, for key: ChunkKey) {
        dropStale(session: key.sessionID, chapterIndex: key.chapterIndex)
        inflight[key] = task
    }

    func finish(_ task: Task<Data, Error>, for key: ChunkKey) {
        if inflight[key] == task { inflight.removeValue(forKey: key) }
    }

    /// Bỏ đoạn / lượt của phiên khác (và của chương khác, nếu có chương).
    private func dropStale(session: UUID, chapterIndex: Int? = nil) {
        func isStale(_ key: ChunkKey) -> Bool {
            key.sessionID != session || (chapterIndex.map { key.chapterIndex != $0 } ?? false)
        }
        for (key, task) in inflight where isStale(key) {
            task.cancel()
            inflight.removeValue(forKey: key)
        }
        if chapterIndex == nil {
            chunkEngines = chunkEngines.filter { !isStale($0.key) }
        }
    }
}
