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

    /// Bản tóm tắt lượt gộp gần nhất, để dựng chip `gốc / sửa / xoá` sau khi **khởi động lại app**.
    ///
    /// Mục thông báo sống theo **file trên đĩa** nên vẫn hiện sau restart, còn `lastOutcome` chỉ sống
    /// trong RAM — không lưu ra `UserDefaults` thì chip biến mất sau mỗi lần mở lại app.
    private struct MergeSummary: Codable {
        let baseCount: Int
        let customCount: Int
        let deletedCount: Int
        let totalCount: Int
    }

    private static let summaryKey = "vietPhraseMergeSummary"

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

    private init() {
        refreshFromDisk()
    }

    var mergedFileURL: URL { DictionaryMergeService.mergedFileURL() }

    /// Số liệu để vẽ chip: ưu tiên `lastOutcome` (vừa gộp xong trong phiên này), rồi tới bản lưu trong
    /// `UserDefaults`, cuối cùng là `nil` — View tự lùi về tổng số từ của file kết quả.
    var summaryCounts: (base: Int, custom: Int, deleted: Int)? {
        if let lastOutcome {
            return (lastOutcome.baseCount, lastOutcome.customCount, lastOutcome.deletedCount)
        }
        guard let data = UserDefaults.standard.data(forKey: Self.summaryKey),
              let summary = try? JSONDecoder().decode(MergeSummary.self, from: data) else {
            return nil
        }
        return (summary.baseCount, summary.customCount, summary.deletedCount)
    }

    /// Tổng số dòng của file kết quả — dùng khi không có số liệu chi tiết.
    var resultRecordCount: Int {
        if let lastOutcome { return lastOutcome.totalCount }
        return DictionaryTextFileStore.loadCount(from: mergedFileURL)
    }

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

    /// Thời điểm dùng để nhóm theo ngày ở màn Thông báo.
    var displayDate: Date {
        if let attributes = try? FileManager.default.attributesOfItem(atPath: mergedFileURL.path),
           let modified = attributes[.modificationDate] as? Date {
            return modified
        }
        return startedAt ?? Date()
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
    func refreshFromDisk() {
        guard hasResult else {
            if case .ready = phase { phase = .idle }
            return
        }
        if let lastOutcome {
            phase = .ready(recordCount: lastOutcome.totalCount)
        } else {
            phase = .ready(recordCount: DictionaryTextFileStore.loadCount(from: mergedFileURL))
        }
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
            persistSummary(outcome)
            phase = .ready(recordCount: outcome.totalCount)
        } else {
            phase = .failed(message: failureMessage ?? "Gộp thất bại.")
        }
    }

    /// Ghi số liệu lượt gộp ra `UserDefaults` — xem doc ở `MergeSummary`.
    private func persistSummary(_ outcome: DictionaryMergeService.Outcome) {
        let summary = MergeSummary(
            baseCount: outcome.baseCount,
            customCount: outcome.customCount,
            deletedCount: outcome.deletedCount,
            totalCount: outcome.totalCount
        )
        guard let data = try? JSONEncoder().encode(summary) else { return }
        UserDefaults.standard.set(data, forKey: Self.summaryKey)
    }

    /// Xoá số liệu đã lưu — gọi khi file kết quả không còn (đã nhập hoặc bỏ qua).
    private func clearSummary() {
        UserDefaults.standard.removeObject(forKey: Self.summaryKey)
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
        lastOutcome = nil
        clearSummary()
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
        lastOutcome = nil
        clearSummary()
        phase = .idle
    }
}
