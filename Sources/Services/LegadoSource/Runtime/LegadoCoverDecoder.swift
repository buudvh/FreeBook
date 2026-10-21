import Foundation

/// `coverDecodeJs` của nguồn Legado (spec §8.7): byte ảnh bìa vừa tải → JS của nguồn → byte ảnh dùng để hiển thị/cache.
///
/// Hai bộ tải bìa của app gọi vào đây **trước** bước kiểm "có phải ảnh" (bìa đã mã hoá không phải ảnh):
/// - `CoverImageLoader` (kết quả tìm kiếm / Khám phá, cache ở `Caches`) không biết nguồn ⇒ tra **sổ đăng ký** URL bìa mà
///   runtime ghi lúc trả kết quả (`register`) — chỉ cho nguồn có `coverDecodeJs`, nên tiện ích JS chỉ tốn một lần tra
///   từ điển (thường rỗng).
/// - `ImageCacheManager.downloadAndSaveCover` (kệ, trang sách — `covers/<sha256(bookId)>.jpg`) có `packageId` ⇒ dùng
///   được cả sau khi mở lại app (sổ đăng ký rỗng).
///
/// Giải mã chạy một phiên engine (không mạng) mỗi bìa, tối đa `maxConcurrentDecodes` phiên cùng lúc. Lỗi/không ra ảnh
/// ⇒ trả **byte gốc**, log `❌` một lần cho mỗi nguồn trong phiên chạy app.
final class LegadoCoverDecoder: @unchecked Sendable {
    static let shared = LegadoCoverDecoder()

    /// Việc giải mã một bìa: nguồn đã nạp, mã JS, và `src` (URL bìa nguyên văn, gồm khối option nếu có — biến `src`).
    struct Plan: Sendable {
        let target: LegadoSourceRuntime.Target
        let code: String
        let src: String
    }

    private struct Registration {
        let packageId: String
        let src: String
    }

    static let maxConcurrentDecodes = 2
    static let decodeSeconds = 15
    private static let registryCapacity = 2000

    private let lock = NSLock()
    /// URL bìa hiển thị (đã trim, đúng chuỗi `ExtensionItemResult.cover` / `NovelDetailResult.cover`) → nguồn + `src`.
    private var registry: [String: Registration] = [:]
    private var loggedFailures: Set<String> = []
    private var running = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    private init() {}

    // MARK: - Sổ đăng ký (runtime gọi)

    /// Ghi URL bìa của các mục vừa trả về (tìm kiếm, khám phá, trang sách). Nguồn không có `coverDecodeJs` ⇒ bỏ qua.
    func register(rawCoverURLs: [String], target: LegadoSourceRuntime.Target) {
        guard !Self.code(of: target).isEmpty else { return }
        var pairs: [(String, Registration)] = []
        for raw in rawCoverURLs {
            let display = LegadoSourceRuntime.displayCoverURL(raw).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !display.isEmpty else { continue }
            let src = LegadoSourceRuntime.trimmed(raw)
            pairs.append((display, Registration(packageId: target.packageId, src: src.isEmpty ? display : src)))
        }
        guard !pairs.isEmpty else { return }
        lock.lock()
        if registry.count + pairs.count > Self.registryCapacity { registry.removeAll(keepingCapacity: true) }
        for (key, value) in pairs { registry[key] = value }
        lock.unlock()
    }

    // MARK: - Tra (bộ tải bìa gọi, thread bất kỳ)

    /// Việc giải mã cho bìa `url`, `nil` khi không cần (tiện ích JS, nguồn không có `coverDecodeJs`). Sổ đăng ký trước,
    /// rồi tới `packageId` của sách (nếu có). Lần đầu với một nguồn có thể đọc `source.json` — đừng gọi trên main.
    func plan(url: String, packageId: String?) -> Plan? {
        let key = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }
        lock.lock()
        let registered = registry[key]
        lock.unlock()
        guard let resolvedId = registered?.packageId ?? LegadoSourceRuntime.nonEmpty(packageId),
              let ext = ExtensionLibraryRepository.snapshot(packageId: resolvedId),
              LegadoSourceIdentity.isLegado(ext),
              let target = try? LegadoSourceTargetResolver.shared.target(localPath: ext.localPath) else { return nil }
        let code = Self.code(of: target)
        guard !code.isEmpty else { return nil }
        return Plan(target: target, code: code, src: registered?.src ?? key)
    }

    // MARK: - Giải mã

    /// Byte đã giải mã; lỗi, hết giờ hay JS không trả ảnh ⇒ `data` gốc (log `❌` một lần cho nguồn này). Huỷ ⇒ `data`.
    func decode(_ data: Data, plan: Plan) async -> Data {
        guard !data.isEmpty else { return data }
        await acquireSlot()
        defer { releaseSlot() }
        if Task.isCancelled { return data }
        let log = LegadoRunLog()
        let target = plan.target
        let code = plan.code
        let src = plan.src
        do {
            let decoded = try await LegadoCorpusDeadline.run(seconds: Self.decodeSeconds) { () async throws -> Data? in
                try await LegadoSourceRuntime.runSession(target, log: log) { (session: LegadoEngineSession) throws -> Data? in
                    try LegadoSourceRuntime.runImageDecode(session: session, code: code, bytes: data, src: src,
                                                           field: "coverDecodeJs")
                }
            }
            guard let decoded else {
                let reason = log.entries.last(where: { $0.kind == "javaScript" })?.message
                    ?? log.entries.last?.message ?? "không trả ảnh"
                noteFailure(target, reason: reason)
                return data
            }
            return decoded
        } catch is CancellationError {
            return data
        } catch is LegadoCorpusDeadline.Exceeded {
            noteFailure(target, reason: "quá \(Self.decodeSeconds) giây")
            return data
        } catch {
            noteFailure(target, reason: error.localizedDescription)
            return data
        }
    }

    // MARK: - Nội bộ

    private static func code(of target: LegadoSourceRuntime.Target) -> String {
        LegadoSourceRuntime.scriptBody(target.source.coverDecodeJs)
    }

    /// Một dòng `❌` cho mỗi nguồn trong phiên chạy app (danh sách dài cùng một nguồn hỏng không làm ngập log).
    private func noteFailure(_ target: LegadoSourceRuntime.Target, reason: String) {
        lock.lock()
        let isFirst = loggedFailures.insert(target.packageId).inserted
        lock.unlock()
        guard isFirst else { return }
        let detail = LegadoCorpusErrorClassifier.redact(String(reason.prefix(200)))
        AppLogger.shared.log("❌ [LegadoCover] coverDecodeJs của nguồn \(target.source.bookSourceName) lỗi — dùng ảnh gốc: \(detail)")
    }

    private func acquireSlot() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            enqueueOrResume(continuation)
        }
    }

    private func enqueueOrResume(_ continuation: CheckedContinuation<Void, Never>) {
        lock.lock()
        if running < Self.maxConcurrentDecodes {
            running += 1
            lock.unlock()
            continuation.resume()
            return
        }
        waiters.append(continuation)
        lock.unlock()
    }

    /// Trao lượt thẳng cho người chờ đầu hàng (giữ nguyên `running`) hoặc trả lượt.
    private func releaseSlot() {
        lock.lock()
        guard !waiters.isEmpty else {
            running = max(0, running - 1)
            lock.unlock()
            return
        }
        let next = waiters.removeFirst()
        lock.unlock()
        next.resume()
    }
}
