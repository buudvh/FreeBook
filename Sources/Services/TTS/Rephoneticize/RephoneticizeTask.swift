import Combine
import Foundation

/// Trạng thái + hành động hậu-"Phiên âm lại" cho **một** từ điển phiên âm, hiện ở màn **Thông báo**.
///
/// Khuôn y `DictionaryMergeTask` (cùng lý do, cùng cách chữa): nguồn sự thật của trạng thái là **file trên
/// đĩa** (plist kết quả + file meta JSON kèm theo), không phải biến trong RAM — nhờ vậy mục thông báo còn
/// sau khi tắt app mà không cần thêm persistence nào, và người dùng luôn thấy đúng thứ đang nằm trên máy.
///
/// ## Vì sao số liệu nằm ở JSON, **không** parse plist
/// Bài học 1.3.448: màn Thông báo từng parse cả `VietPhraseMerged.txt` (~1,4 triệu dòng) **trên main
/// thread** mỗi lần render ⇒ đơ app và nghẽn luôn TTS. Ở đây `init` chỉ đọc file meta vài trăm byte. Đó là
/// lý do tồn tại của `RephoneticizeService.Meta` — **đừng** đổi sang đếm lại từ plist, và đừng để `body`
/// của View chạm đĩa.
///
/// ## Hai instance, hai từ điển
/// Hai từ điển độc lập hoàn toàn nên mỗi cái có task riêng: chạy song song được, card này không che card
/// kia, và một lượt lỗi ở từ điển này không chặn từ điển kia.
@MainActor
final class RephoneticizeTask: ObservableObject {
    static let nghiTTS = RephoneticizeTask(target: .nghiTTS)
    static let vieNeu = RephoneticizeTask(target: .vieNeu)

    enum Phase: Equatable {
        case idle
        case running(progress: Double)
        case ready(recordCount: Int)
        case failed(message: String)
    }

    let target: RephoneticizeService.Target

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var lastOutcome: RephoneticizeService.Outcome?
    /// Thời điểm bắt đầu lượt gần nhất — dùng để xếp mục thông báo vào đúng ngày khi chưa có meta.
    @Published private(set) var startedAt: Date?
    /// Số liệu đọc từ file meta kèm theo. `nil` = chưa chạy lần nào hoặc meta không đọc được.
    @Published private(set) var meta: RephoneticizeService.Meta?

    private init(target: RephoneticizeService.Target) {
        self.target = target
        refreshFromDisk()
    }

    var resultFileURL: URL? { RephoneticizeService.resultFileURL(for: target) }

    var title: String { "Phiên âm lại từ điển \(target.displayName)" }

    /// Số liệu để vẽ chip: ưu tiên `lastOutcome` (vừa chạy xong trong phiên này ⇒ chip hiện **ngay**, không
    /// phải chờ đọc lại file), rồi tới file meta. Cả hai đều **thuần RAM** sau lượt `refreshFromDisk`.
    var summaryCounts: (total: Int, changed: Int, kept: Int, merged: Int)? {
        if let lastOutcome {
            return (lastOutcome.totalCount, lastOutcome.changedCount, lastOutcome.keptCount, lastOutcome.keysMergedCount)
        }
        guard let meta else { return nil }
        return (meta.totalCount, meta.changedCount, meta.keptCount, meta.keysMergedCount)
    }

    /// Tổng số mục của file kết quả — **không** đọc plist kết quả (xem doc `Meta`).
    var resultRecordCount: Int {
        if let lastOutcome { return lastOutcome.totalCount }
        return meta?.totalCount ?? 0
    }

    /// `true` khi có file kết quả nhưng **không** đọc được meta (meta bị xoá hoặc từ bản app khác).
    /// View dùng cờ này để nói rõ "số liệu chưa có — chạy lại để cập nhật" thay vì parse plist để đếm.
    var isMetaMissing: Bool { hasResult && meta == nil }

    var hasResult: Bool { RephoneticizeService.hasResult(for: target) }

    var isRunning: Bool {
        if case .running = phase { return true }
        return false
    }

    var isFailed: Bool {
        if case .failed = phase { return true }
        return false
    }

    /// Mục thông báo có nên hiện không: đang chạy, có file kết quả, hoặc vừa lỗi.
    var isVisible: Bool {
        if isRunning || hasResult { return true }
        if case .failed = phase { return true }
        return false
    }

    /// Thời điểm dùng để nhóm theo ngày ở màn Thông báo — đọc từ meta (`createdAt`), **không** gọi
    /// `attributesOfItem` mỗi lần render.
    var displayDate: Date {
        meta?.createdAt ?? startedAt ?? Date()
    }

    /// Tiến độ 0…1 khi đang chạy, `nil` khi không — để View vẽ `ProgressView` mà không phải pattern-match
    /// `phase` ngay trong `ViewBuilder`.
    var runningProgress: Double? {
        if case .running(let progress) = phase { return progress }
        return nil
    }

    var statusText: String {
        switch phase {
        case .idle:
            return hasResult ? "Có kết quả chờ xử lý" : "Chưa phiên âm lại"
        case .running(let progress):
            return "Đang phiên âm… \(Int((progress * 100).rounded()))%"
        case .ready(let count):
            return "Xong: \(count) mục"
        case .failed(let message):
            return message
        }
    }

    // MARK: - Đọc lại từ đĩa

    /// Đọc lại trạng thái từ **đĩa**. Gọi ở `init` và sau mỗi thao tác đổi file.
    ///
    /// Nay chỉ đọc **file meta vài trăm byte** (thay vì parse cả plist) nên chạy thẳng trên `MainActor` là
    /// an toàn — kể cả trong `init` của singleton, chỗ từng chặn main lúc mở app ở tính năng gộp VietPhrase.
    func refreshFromDisk() {
        meta = RephoneticizeService.loadMeta(for: target)
        guard hasResult else {
            if case .ready = phase { phase = .idle }
            return
        }
        phase = .ready(recordCount: resultRecordCount)
    }

    // MARK: - Chạy

    func start() {
        guard !isRunning else { return }
        startedAt = Date()
        phase = .running(progress: 0)

        // Closure tiến độ phải `@Sendable` vì nó chạy trong `Task.detached`; nó **không** capture `self`
        // mà đi qua instance dùng chung theo `target`, để mọi cập nhật state đều nằm trên `MainActor`.
        let target = self.target
        let progressHandler: @Sendable (Double) -> Void = { fraction in
            Task { @MainActor in
                RephoneticizeTask.instance(for: target).updateProgress(fraction)
            }
        }

        Task.detached(priority: .utility) {
            var outcome: RephoneticizeService.Outcome?
            var failureMessage: String?
            do {
                outcome = try await RephoneticizeService.run(target: target, progress: progressHandler)
            } catch {
                failureMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            await MainActor.run {
                RephoneticizeTask.instance(for: target).finish(outcome: outcome, failureMessage: failureMessage)
            }
        }
    }

    /// Lấy instance dùng chung theo đích — để closure `@Sendable` không phải capture `self`.
    static func instance(for target: RephoneticizeService.Target) -> RephoneticizeTask {
        switch target {
        case .nghiTTS: return nghiTTS
        case .vieNeu: return vieNeu
        }
    }

    private func updateProgress(_ fraction: Double) {
        guard case .running = phase else { return }
        phase = .running(progress: fraction)
    }

    private func finish(outcome: RephoneticizeService.Outcome?, failureMessage: String?) {
        if let outcome {
            lastOutcome = outcome
            // Meta đã được `RephoneticizeService.run` ghi cùng lượt; đọc lại để state khớp đĩa.
            meta = RephoneticizeService.loadMeta(for: target)
            phase = .ready(recordCount: outcome.totalCount)
        } else {
            phase = .failed(message: failureMessage ?? "Phiên âm lại thất bại.")
        }
    }

    // MARK: - Hậu phiên âm lại

    /// Closure chuẩn hoá khoá của **đúng từ điển này** — đi qua `RephoneticizeService` để file kết quả và
    /// màn chọn mục trùng dùng **một** định nghĩa (lệch nhau ⇒ sinh mục trùng giả hoặc sót mục thật).
    var normalizedKey: @Sendable (String) -> String {
        let resolved = target
        return { RephoneticizeService.normalizedKey($0, target: resolved) }
    }

    /// Đọc từ điển **đang dùng** — truyền cho màn chọn mục trùng để màn tự đọc **lúc mở**, không nhận ảnh
    /// chụp từ caller (ảnh chụp có thể cũ ở thời điểm người dùng bấm Áp dụng).
    var currentWordsProvider: @Sendable () async -> [String: String] {
        let resolved = target
        return { await RephoneticizeService.currentWords(for: resolved) }
    }

    /// Áp file kết quả vào **từ điển đang dùng**, sau khi **sao lưu** bản hiện có.
    ///
    /// Sao lưu là bắt buộc: đây là lượt ghi đè **toàn bộ** từ điển (NghiTTS ~30k mục), không có đường lùi
    /// nào khác nếu file kết quả sai.
    func apply() async throws {
        guard let resultURL = resultFileURL,
              FileManager.default.fileExists(atPath: resultURL.path) else { return }

        let data = try Data(contentsOf: resultURL)
        guard let words = ((try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: String]),
              !words.isEmpty else {
            throw NSError(
                domain: "RephoneticizeTask",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "File kết quả không phải plist dạng từ điển chuỗi."]
            )
        }

        try await write(words)
    }

    /// Nhánh **Trộn**: ghi một bảng đã người dùng chọn từng mục. Hành vi y hệt `apply()` chỉ khác ở chỗ
    /// bảng đến từ màn chọn mục trùng thay vì đọc thẳng từ file kết quả.
    func applyMerged(_ words: [String: String]) async throws {
        guard !words.isEmpty else { return }
        try await write(words)
    }

    /// Đường ghi **duy nhất** — cả hai nhánh đều đi qua đây để không bao giờ lệch nhau ở bước **sao lưu**
    /// hay bước dọn file kết quả.
    private func write(_ words: [String: String]) async throws {
        try Self.backUpLiveDictionary(for: target)

        switch target {
        case .nghiTTS:
            try await TextPreprocessor.shared.replaceAllWords(words)
        case .vieNeu:
            try await VieNeuJapaneseDictionary.shared.replaceAll(words)
        }

        if let url = resultFileURL { try? FileManager.default.removeItem(at: url) }
        RephoneticizeService.deleteMeta(for: target)
        lastOutcome = nil
        meta = nil
        phase = .idle
    }

    /// Sao lưu file từ điển **đang dùng** sang `<tên>.bak-rephoneticize` (cùng thư mục `FreeBook/TTS/`).
    static func backUpLiveDictionary(for target: RephoneticizeService.Target) throws {
        guard let live = RephoneticizeService.liveDictionaryURL(for: target),
              let backup = RephoneticizeService.backupURL(for: target),
              FileManager.default.fileExists(atPath: live.path) else { return }
        try? FileManager.default.removeItem(at: backup)
        try FileManager.default.copyItem(at: live, to: backup)
    }

    /// Bỏ file kết quả (không đụng từ điển đang dùng).
    func discardResult() {
        if let url = resultFileURL { try? FileManager.default.removeItem(at: url) }
        RephoneticizeService.deleteMeta(for: target)
        lastOutcome = nil
        meta = nil
        phase = .idle
    }
}
