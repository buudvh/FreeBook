import Combine
import Foundation

/// Trạng thái + hành động hậu-gộp cho mục "Gộp VietPhrase" ở màn **Thông báo**.
///
/// Nguồn sự thật của trạng thái là **file kết quả trên đĩa** (`VietPhraseMerged.txt`), không phải biến
/// trong RAM: nhờ vậy mục thông báo vẫn còn sau khi tắt app mà không cần thêm persistence nào, và người
/// dùng luôn thấy đúng thứ đang nằm trên máy.
///
/// Luồng (chốt với user 2026-09-30): **Gộp** → sinh `VietPhraseMerged.txt` (không đụng từ điển gốc) →
/// người dùng chọn **Nhập vào VietPhrase** (đi qua `TranslationManager.importDictionary`, đường đã có) hoặc
/// **Xuất file** → sau khi nhập thì xoá custom + tombstone.
@MainActor
final class DictionaryMergeTask: ObservableObject {
    static let shared = DictionaryMergeTask()

    /// Bản tóm tắt lượt gộp gần nhất nay nằm ở **file meta kèm theo** (`VietPhraseMerged.meta.json`) —
    /// xem `DictionaryMergeService.Meta`. Trước đây nó ở `UserDefaults` nhưng lại **không** được nối vào
    /// `resultRecordCount`, nên nhánh đọc-parse `VietPhraseMerged.txt` vẫn còn và làm đơ app sau restart.
    /// File meta là nguồn sự thật duy nhất, đúng tinh thần "nguồn sự thật là file trên đĩa" của type này.
    enum Phase: Equatable {
        case idle
        case running(progress: Double)
        case ready(recordCount: Int)
        case failed(message: String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var lastOutcome: DictionaryMergeService.Outcome?
    /// Thời điểm bắt đầu lượt gộp gần nhất — dùng để xếp mục thông báo vào đúng ngày khi chưa có file.
    @Published private(set) var startedAt: Date?
    /// Số liệu đọc từ file meta kèm theo. `nil` = chưa có meta (file `.txt` từ bản cũ, hoặc chưa gộp lần nào).
    @Published private(set) var meta: DictionaryMergeService.Meta?

    private init() {
        // Dọn khoá `UserDefaults` của bản cũ (số liệu nay nằm ở file meta kèm theo).
        UserDefaults.standard.removeObject(forKey: "vietPhraseMergeSummary")
        refreshFromDisk()
    }

    var mergedFileURL: URL { DictionaryMergeService.mergedFileURL() }

    /// Số liệu để vẽ chip: ưu tiên `lastOutcome` (vừa gộp xong trong phiên này ⇒ chip hiện **ngay**, không
    /// phải chờ đọc lại file), rồi tới file meta. Cả hai đều **thuần RAM** sau lượt `refreshFromDisk`.
    var summaryCounts: (base: Int, custom: Int, deleted: Int)? {
        if let lastOutcome {
            return (lastOutcome.baseCount, lastOutcome.customCount, lastOutcome.deletedCount)
        }
        guard let meta else { return nil }
        return (meta.baseCount, meta.customCount, meta.deletedCount)
    }

    /// Tổng số dòng của file kết quả — **không** đọc `VietPhraseMerged.txt` (xem doc `Meta`).
    var resultRecordCount: Int {
        if let lastOutcome { return lastOutcome.totalCount }
        return meta?.totalCount ?? 0
    }

    /// `true` khi có file kết quả nhưng **không** đọc được meta (file `.txt` sinh từ bản app cũ).
    /// View dùng cờ này để hiện dòng phụ "Số liệu chưa có — gộp lại để cập nhật".
    var isMetaMissing: Bool { hasResult && meta == nil }

    var hasResult: Bool { FileManager.default.fileExists(atPath: mergedFileURL.path) }

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
    /// `attributesOfItem` mỗi lần render như trước.
    var displayDate: Date {
        meta?.createdAt ?? startedAt ?? Date()
    }

    /// Tiến độ 0…1 khi đang gộp, `nil` khi không chạy — để View vẽ `ProgressView` mà không phải
    /// pattern-match `phase` ngay trong `ViewBuilder`.
    var runningProgress: Double? {
        if case .running(let progress) = phase { return progress }
        return nil
    }

    var statusText: String {
        switch phase {
        case .idle:
            return hasResult ? "Có file gộp chờ xử lý" : "Chưa gộp"
        case .running(let progress):
            return "Đang gộp… \(Int((progress * 100).rounded()))%"
        case .ready(let count):
            return "Xong: \(count) từ"
        case .failed(let message):
            return message
        }
    }

    // MARK: - Đọc lại từ đĩa

    /// Đọc lại trạng thái từ **đĩa**. Gọi ở `init` và sau mỗi thao tác đổi file.
    ///
    /// Nay chỉ đọc **file meta vài trăm byte** (thay vì parse cả `VietPhraseMerged.txt`) nên chạy thẳng trên
    /// `MainActor` là an toàn — kể cả trong `init` của singleton, chỗ từng chặn main lúc mở app.
    func refreshFromDisk() {
        meta = DictionaryMergeService.loadMeta()
        guard hasResult else {
            if case .ready = phase { phase = .idle }
            return
        }
        phase = .ready(recordCount: resultRecordCount)
    }

    // MARK: - Gộp

    func startMerge() {
        guard !isRunning else { return }
        startedAt = Date()
        phase = .running(progress: 0)

        // Closure tiến độ phải `@Sendable` vì nó chạy trong `Task.detached`; nó **không** capture `self`
        // mà đi qua singleton để mọi cập nhật state đều nằm trên `MainActor`.
        let progressHandler: @Sendable (Double) -> Void = { fraction in
            Task { @MainActor in
                DictionaryMergeTask.shared.updateProgress(fraction)
            }
        }

        Task.detached(priority: .utility) {
            var outcome: DictionaryMergeService.Outcome?
            var failureMessage: String?
            do {
                outcome = try DictionaryMergeService.merge(progress: progressHandler)
            } catch {
                failureMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            await MainActor.run {
                DictionaryMergeTask.shared.finish(outcome: outcome, failureMessage: failureMessage)
            }
        }
    }

    fileprivate func updateProgress(_ fraction: Double) {
        guard case .running = phase else { return }
        phase = .running(progress: fraction)
    }

    fileprivate func finish(outcome: DictionaryMergeService.Outcome?, failureMessage: String?) {
        if let outcome {
            lastOutcome = outcome
            // Meta đã được `DictionaryMergeService.merge` ghi cùng lượt; đọc lại để state khớp đĩa.
            meta = DictionaryMergeService.loadMeta()
            phase = .ready(recordCount: outcome.totalCount)
        } else {
            phase = .failed(message: failureMessage ?? "Gộp thất bại.")
        }
    }

    // MARK: - Hậu gộp

    /// Nhập file gộp vào **từ điển VietPhrase gốc**, rồi xoá custom + tombstone.
    ///
    /// `importDictionary` **xoá** `VietPhrase.dat` rồi biên dịch lại từ text, nên bắt buộc sao lưu trước:
    /// biên dịch lỗi giữa chừng là mất từ điển gốc nếu không có bản `.bak-merge`.
    func applyToVietPhrase() async throws {
        let url = mergedFileURL
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let manager = TranslationManager.shared

        try Self.backUpBaseDictionary()
        try await manager.importDictionary(from: url, type: "vietphrase")

        // Custom + tombstone đã nằm trong file vừa nhập ⇒ xoá để không còn tầng phủ nào.
        try DictionaryTextFileStore.persist(
            records: [],
            to: manager.customTextURL(isName: false, bookId: nil)
        )
        await manager.reloadCustomDictionary(isName: false)
        manager.notifyDictionariesDidUpdate()

        try? FileManager.default.removeItem(at: url)
        // Xoá meta **cùng lượt** với file kết quả — không để meta mồ côi.
        DictionaryMergeService.deleteMeta()
        lastOutcome = nil
        meta = nil
        phase = .idle
    }

    /// Sao lưu `VietPhrase.dat` hiện tại sang `VietPhrase.dat.bak-merge` (cùng thư mục `translate/`).
    static func backUpBaseDictionary() throws {
        let directory = TranslationManager.shared.translateDirectory
        let dat = directory.appendingPathComponent("VietPhrase.dat")
        guard FileManager.default.fileExists(atPath: dat.path) else { return }
        let backup = directory.appendingPathComponent(DictionaryMergeService.backupFileName)
        try? FileManager.default.removeItem(at: backup)
        try FileManager.default.copyItem(at: dat, to: backup)
    }

    /// Bỏ file kết quả (không đụng từ điển gốc lẫn custom).
    func discardResult() {
        try? FileManager.default.removeItem(at: mergedFileURL)
        DictionaryMergeService.deleteMeta()
        lastOutcome = nil
        meta = nil
        phase = .idle
    }
}
