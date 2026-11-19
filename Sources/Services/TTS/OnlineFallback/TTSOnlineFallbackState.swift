import Foundation

/// Trạng thái **lúc chạy** của giọng dự phòng (1.3.945) — `TTSManager` giữ một bản (`onlineFallback`), chỉ chạm trên main.
///
/// - Bật theo **phiên** TTS (`sessionID`): phiên mới ⇒ coi như đang đọc online, đoạn đầu thử online lại.
/// - `chunkEngines`: đoạn nào có tiếng do giọng dự phòng tạo — để phát đúng tốc độ của engine dự phòng và hiện badge
///   "Dự phòng", kể cả sau khi đã quay lại online (đoạn dự phòng đã nạp trước vẫn phát hết).
/// - `inflight`: lượt tổng hợp dự phòng đang chạy theo đoạn — đoạn đang đọc và lượt nạp trước của cùng đoạn dùng chung một
///   lượt. `waiters` đếm người đang chờ từng đoạn: người chờ bị huỷ (bỏ qua đoạn, tạm dừng, online về trước lượt đọc song
///   song) mà không còn ai chờ ⇒ huỷ lượt (1.3.960 — trước đó lượt chạy nốt rồi bỏ kết quả, đoạn mới phải chờ sau nó).
///   Dọn hết ở `forgetChunks()` (xoá bộ đệm TTS: dừng đọc, đổi cài đặt…) và khi lệch phiên / chương.
/// - Đọc song song (`TTSManager+OnlineFallbackHedge`, 1.3.960): `hedgeTask` của đoạn đang đọc, `deliveredPlaybackId` = lượt
///   phát đã có tiếng (online hoặc dự phòng) — bên về sau không phát chồng.
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
    /// Lượt đã rời hàng chờ nối đuôi và đang ở / sắp vào hàng đợi tổng hợp. Lượt nạp trước chưa có mặt ở đây còn xếp sau
    /// lượt khác ⇒ đoạn đang đọc không dùng chung nó mà tạo lượt mới đi thẳng (1.3.957).
    private var started: Set<ChunkKey> = []
    /// Lượt **nạp trước** tạo gần nhất: lượt nạp trước kế tiếp chờ nó xong rồi mới vào hàng đợi tổng hợp, nên các đoạn dự
    /// phòng được tổng hợp đúng thứ tự tạo (đoạn gần trước).
    private(set) var prefetchTail: Task<Data, Error>?
    var probeTask: Task<Void, Never>?
    /// Người đang chờ từng lượt (mỗi lần gọi `TTSManager.onlineFallbackAudio` một mã).
    private var waiters: [ChunkKey: Set<UUID>] = [:]
    /// Lượt đọc song song của đoạn đang đọc và đoạn của nó.
    var hedgeTask: Task<Void, Never>?
    var hedgeKey: ChunkKey?
    private var deliveredPlaybackId: String?
    /// Phiên đã nạp sẵn engine dự phòng (`TTSManager.prewarmOnlineFallback`) — mỗi phiên một lần.
    private var prewarmedSession: UUID?

    /// `true` nếu phiên này chưa nạp sẵn engine dự phòng (và đánh dấu là đã nạp).
    func claimPrewarm(session: UUID) -> Bool {
        guard prewarmedSession != session else { return false }
        prewarmedSession = session
        return true
    }

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

    /// Bộ đệm TTS bị xoá ⇒ tiếng đã nạp không còn: quên đoạn và mọi lượt đang chạy (kể cả lượt đọc song song).
    func forgetChunks() {
        chunkEngines.removeAll()
        for task in inflight.values { task.cancel() }
        inflight.removeAll()
        started.removeAll()
        waiters.removeAll()
        prefetchTail = nil
        cancelHedge()
    }

    /// Các đoạn `indices` của chương đang đọc vừa đổi chữ (dịch lại khi đang nghe, `TTSManager+RetranslationSplice`) ⇒ quên
    /// dấu "dự phòng" + lượt tổng hợp của **đúng** các đoạn đó. Không dùng `forgetChunks()`: đoạn giữ nguyên chữ phải giữ tốc
    /// độ / badge dự phòng của tiếng đã nạp. Lượt đang chạy khoá theo chỉ số (không theo chữ) ⇒ không gỡ thì lượt nạp mới
    /// của đoạn dùng chung lượt cũ, phát chữ cũ.
    func forgetChunks(_ indices: Set<Int>, session: UUID, chapterIndex: Int) {
        func isTarget(_ key: ChunkKey) -> Bool {
            key.sessionID == session && key.chapterIndex == chapterIndex && indices.contains(key.index)
        }
        for (key, task) in inflight where isTarget(key) {
            task.cancel()
            inflight.removeValue(forKey: key)
            started.remove(key)
        }
        waiters = waiters.filter { !isTarget($0.key) }
        chunkEngines = chunkEngines.filter { !isTarget($0.key) }
        if let hedgeKey, isTarget(hedgeKey) { cancelHedge() }
    }

    // MARK: - Đọc song song

    func cancelHedge() {
        hedgeTask?.cancel()
        hedgeTask = nil
        hedgeKey = nil
    }

    /// Lượt phát `playbackId` vừa có tiếng ⇒ `true` nếu bên gọi là bên **đầu tiên** (được phát).
    func claimDelivery(_ playbackId: String) -> Bool {
        guard deliveredPlaybackId != playbackId else { return false }
        deliveredPlaybackId = playbackId
        return true
    }

    func isDelivered(_ playbackId: String) -> Bool {
        deliveredPlaybackId == playbackId
    }

    // MARK: - Người chờ

    func addWaiter(_ token: UUID, for key: ChunkKey) {
        waiters[key, default: []].insert(token)
    }

    /// Người chờ rời đi. `cancelIfIdle` (người chờ bị huỷ) + không còn ai chờ `task` ⇒ huỷ lượt đó và gỡ khỏi `inflight`
    /// ngay, để người tới sau tạo lượt mới thay vì dùng chung một lượt đã huỷ (sẽ chỉ nhận `CancellationError`).
    func removeWaiter(_ token: UUID, for key: ChunkKey, task: Task<Data, Error>, cancelIfIdle: Bool) {
        guard waiters[key]?.remove(token) != nil else { return }
        if waiters[key]?.isEmpty == true { waiters.removeValue(forKey: key) }
        guard cancelIfIdle, waiters[key] == nil, inflight[key] == task else { return }
        task.cancel()
        inflight.removeValue(forKey: key)
        started.remove(key)
    }

    // MARK: - Lượt tổng hợp

    func task(for key: ChunkKey) -> Task<Data, Error>? {
        inflight[key]
    }

    /// `isPrefetch` ⇒ lượt này thành đuôi của hàng nạp trước (`prefetchTail`).
    func store(_ task: Task<Data, Error>, for key: ChunkKey, isPrefetch: Bool) {
        dropStale(session: key.sessionID, chapterIndex: key.chapterIndex)
        inflight[key] = task
        started.remove(key)
        if isPrefetch { prefetchTail = task }
    }

    func finish(_ task: Task<Data, Error>, for key: ChunkKey) {
        // Đuôi đã xong thì thôi giữ (kèm tiếng của nó); lượt sau không còn gì để chờ.
        if prefetchTail == task { prefetchTail = nil }
        guard inflight[key] == task else { return }
        inflight.removeValue(forKey: key)
        started.remove(key)
    }

    func markStarted(_ key: ChunkKey) {
        started.insert(key)
    }

    func hasStarted(_ key: ChunkKey) -> Bool {
        started.contains(key)
    }

    /// Bỏ đoạn / lượt của phiên khác (và của chương khác, nếu có chương).
    private func dropStale(session: UUID, chapterIndex: Int? = nil) {
        func isStale(_ key: ChunkKey) -> Bool {
            key.sessionID != session || (chapterIndex.map { key.chapterIndex != $0 } ?? false)
        }
        for (key, task) in inflight where isStale(key) {
            task.cancel()
            inflight.removeValue(forKey: key)
            started.remove(key)
        }
        waiters = waiters.filter { !isStale($0.key) }
        // Dấu "dự phòng" của chương khác cũng bỏ: quay lại chương đó thì tiếng nạp lại là tiếng mới (1.3.960 — trước đó dấu
        // cũ còn ⇒ đoạn online phát sai tốc độ + hiện badge "Dự phòng").
        chunkEngines = chunkEngines.filter { !isStale($0.key) }
    }
}
