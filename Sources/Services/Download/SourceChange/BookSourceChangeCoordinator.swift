import Foundation
import SwiftData
import UIKit

/// Một lượt **đổi nguồn** truyện (1.3.689): truyện cũ → truyện ở nguồn mới cùng loại nội dung, mang theo chương đã tải,
/// tiến độ và thiết lập riêng, rồi dọn truyện cũ.
///
/// Thứ tự (mốc chốt ở `BookSourceChangeJournal`):
/// 1. Tải chi tiết + mục lục nguồn mới (lỗi ở đây ⇒ chưa đổi gì), rồi mới dừng tải + ghi nốt lệnh ghi đang chờ của truyện cũ.
/// 2. Ghi nhật ký `.copying`, lưu truyện đích + mục lục. Truyện đích = truyện **đã có** trên máy cùng tiện ích + link chi
///    tiết (đổi lại sau lần bị ngắt, hoặc nguồn đó đã có sẵn) ⇒ không tạo bản trùng; không có thì tạo truyện mới (UUID).
/// 3. Chép chương theo lô ngoài main (`BookSourceChapterCopier`), chép thiết lập (`BookSourceMigrator`). Chỉ **chép**:
///    truyện cũ vẫn nguyên vẹn.
/// 4. Ghi `.committed`, trả kết quả để View đóng các màn đang giữ `Book` cũ; `finishDelay` sau mới xoá truyện cũ qua
///    `BookStorageManager.deleteBooksAsync` (context nền) và xoá thiết lập cũ (`+Cleanup`).
///
/// Trước 1.3.689 cả lượt nằm trong `SearchView` và xoá truyện cũ bằng context **main** (cascade `Book.chapters`; truyện
/// thêm trước 27/7/2026 còn hàng nghìn dòng `Chapter` SwiftData). Truyện hơn 2.000 chương làm đơ app, app chết trước khi
/// lưu ⇒ còn hai truyện, thiết lập riêng đã rời truyện cũ.
@MainActor
final class BookSourceChangeCoordinator {
    static let shared = BookSourceChangeCoordinator()

    /// Ảnh chụp **giá trị** của truyện cũ lúc bấm đổi — không giữ instance `Book`, vì nó sắp bị xoá.
    struct Request {
        let oldBookId: String
        let oldTitle: String
        let oldChapterIndex: Int
        let oldIsOnShelf: Bool
        let oldIsHistory: Bool
        let oldLastReadDate: Date
        /// Đang nghe TTS truyện cũ ⇒ giữ truyện cũ để không ngắt quãng nghe.
        let keepsOldBook: Bool
        let result: ExtensionItemResult
        let ext: Extension
    }

    struct Outcome {
        let newBookId: String
        let reusedExistingBook: Bool
        /// Truyện cũ được giữ lại: đang nghe TTS, hoặc có chương chép lỗi (`copyReport.failed > 0`).
        let keptOldBook: Bool
        let isOnShelf: Bool
        let copyReport: BookSourceChapterCopier.Report
    }

    enum Failure: LocalizedError {
        case busy
        case previousUnfinished
        case interrupted
        case journalUnavailable(String)

        var errorDescription: String? {
            switch self {
            case .busy: return "Đang có một lượt đổi nguồn khác chạy"
            case .previousUnfinished: return "Lượt đổi nguồn trước chưa dọn xong, thử lại sau"
            case .interrupted: return "Bị ngắt vì app chuyển nền, truyện cũ giữ nguyên"
            case .journalUnavailable(let reason): return "Không ghi được nhật ký đổi nguồn: \(reason)"
            }
        }
    }

    enum RecoveryResult {
        case none
        /// Lượt dở trước mốc chốt: đã xoá truyện mới, giữ nguyên truyện cũ.
        case rolledBack(BookSourceChangeJournal)
        /// Lượt dở sau mốc chốt: đã dọn nốt truyện cũ.
        case completed(BookSourceChangeJournal)
    }

    /// Chờ View đóng các màn đang giữ instance `Book` cũ (Reader đóng sau 0,3 s + hiệu ứng) rồi mới xoá truyện cũ.
    static let finishDelayNanoseconds: UInt64 = 1_200_000_000

    /// Một lượt đổi nguồn hoặc khôi phục đang chạy (gồm cả bước dọn sau mốc chốt).
    private(set) var isRunning = false
    var backgroundExpired = false
    var backgroundTaskId: UIBackgroundTaskIdentifier = .invalid

    private init() {}

    /// Chạy một lượt đổi nguồn. Trả về ngay sau mốc chốt; việc dọn truyện cũ chạy tiếp ở nền (`scheduleFinish`).
    /// Lỗi trước mốc chốt ⇒ đã lùi lại (xoá truyện mới nếu lượt này tạo ra), truyện cũ nguyên vẹn.
    func run(
        _ request: Request,
        container: ModelContainer,
        onStatus: @escaping @MainActor (String) -> Void
    ) async throws -> Outcome {
        guard !isRunning else { throw Failure.busy }
        isRunning = true
        var finishScheduled = false
        defer { if !finishScheduled { isRunning = false } }

        // Lượt dở của lần trước (bị ngắt khi app ở nền mà chưa mở lại app) ⇒ giải quyết theo đúng luật lúc mở app.
        // Giải quyết chưa xong (xoá lỗi) ⇒ dừng: ghi đè nhật ký đó là mất dấu truyện nửa vời của lượt trước.
        if let pending = BookSourceChangeJournal.load() {
            _ = await resolve(pending, container: container)
            guard BookSourceChangeJournal.load() == nil else { throw Failure.previousUnfinished }
        }

        let existing = await Self.findBook(
            packageId: request.ext.packageId,
            detailUrl: request.result.link,
            excluding: request.oldBookId,
            container: container
        )
        let newBookId = existing?.bookId ?? UUID().uuidString

        onStatus("Đang tải mục lục ở nguồn mới...")
        let source = try await fetchSource(request, newBookId: newBookId)

        // Chỉ dừng tải của truyện cũ khi nguồn mới đã trả mục lục (tra lỗi thì không đổi gì). Ghi nốt chương đang ghi dở
        // (kể cả của tác vụ vừa huỷ) vào ChapterStore trước khi đọc mục lục để chép.
        if !request.keepsOldBook {
            DownloadManager.shared.cancelTasksForBook(bookId: request.oldBookId)
        }
        await ChapterContentRepository.shared.flush(bookId: request.oldBookId)

        var journal = BookSourceChangeJournal(
            oldBookId: request.oldBookId,
            newBookId: newBookId,
            bookTitle: request.oldTitle,
            createdNewBook: existing == nil,
            keepsOldBook: request.keepsOldBook,
            phase: .copying,
            startedAt: Date()
        )
        do {
            try journal.save()
        } catch {
            throw Failure.journalUnavailable(error.localizedDescription)
        }
        AppLogger.shared.log("[SourceChange] Bắt đầu \(request.oldBookId) → \(newBookId) | dùng lại truyện có sẵn: \(existing != nil) | \(source.chapters.count) chương")

        let report: BookSourceChapterCopier.Report
        do {
            _ = try await ChapterContentRepository.shared.saveChapterList(
                bookId: newBookId,
                createSnapshot: source.createSnapshot,
                chapters: source.chapters,
                mode: .replaceFullTOC
            )
            onStatus("Đang chép chương đã tải...")
            beginBackgroundTime()
            defer { endBackgroundTime() }
            report = try await BookSourceChapterCopier.copy(
                oldBookId: request.oldBookId,
                newBookId: newBookId,
                progress: { copied, total in
                    guard total > 0 else { return }
                    await onStatus("Đang chép chương đã tải \(copied)/\(total)...")
                },
                shouldStop: { await BookSourceChangeCoordinator.shared.backgroundExpired }
            )
        } catch {
            AppLogger.shared.log("❌ [SourceChange] Lỗi trước mốc chốt, lùi lại: \(error.localizedDescription)")
            await rollBack(journal, container: container)
            throw error
        }
        // Nhật ký giữ `.copying`: lần app hoạt động lại (`recoverIfNeeded`) sẽ lùi — không xoá gì khi app đang ở nền.
        if report.stopped { throw Failure.interrupted }

        onStatus("Đang chép thiết lập riêng của truyện...")
        await BookSourceMigrator.shared.copyBookScopedSettings(from: request.oldBookId, to: newBookId)
        if let existing {
            // Tiến độ của bản đọc gần hơn: đọc tiếp ở truyện đích sau lần đổi trước thì không bị lùi về chỗ của truyện cũ.
            var oldProgress: (chapterIndex: Int, chapterTitle: String)?
            if request.oldLastReadDate > existing.lastReadDate {
                oldProgress = (chapterIndex: source.createSnapshot.currentChapterIndex,
                               chapterTitle: source.createSnapshot.currentChapterTitle)
            }
            let merged = BookTransactionCoordinator.shared.mergeSourceChangeState(
                bookId: newBookId,
                progress: oldProgress,
                isOnShelf: request.oldIsOnShelf,
                isHistory: request.oldIsHistory,
                in: ModelContext(container)
            )
            if case .failure(let error) = merged {
                AppLogger.shared.log("❌ [SourceChange] Không gộp được tiến độ vào truyện có sẵn: \(error.localizedDescription)")
            }
        }

        journal.keepsOldBook = request.keepsOldBook || report.failed > 0
        journal.phase = .committed
        let outcome = Outcome(
            newBookId: newBookId,
            reusedExistingBook: existing != nil,
            keptOldBook: journal.keepsOldBook,
            isOnShelf: request.oldIsOnShelf || existing?.isOnShelf == true,
            copyReport: report
        )
        do {
            try journal.save()
        } catch {
            // Không ghi được mốc chốt ⇒ không xoá gì (để nhật ký `.copying` lại thì lần sau sẽ xoá nhầm truyện mới đã đủ).
            AppLogger.shared.log("❌ [SourceChange] Không ghi được mốc chốt, giữ cả hai truyện: \(error.localizedDescription)")
            BookSourceChangeJournal.clear()
            return Outcome(newBookId: newBookId, reusedExistingBook: existing != nil, keptOldBook: true,
                           isOnShelf: outcome.isOnShelf, copyReport: report)
        }
        finishScheduled = true
        scheduleFinish(journal, container: container)
        return outcome
    }

    /// Lượt dở của lần chạy trước (app chết, hoặc bị ngắt khi ở nền). Gọi lúc mở app và mỗi lần app hoạt động lại.
    func recoverIfNeeded(container: ModelContainer) async -> RecoveryResult {
        guard !isRunning, let journal = BookSourceChangeJournal.load() else { return .none }
        isRunning = true
        defer { isRunning = false }
        AppLogger.shared.log("[SourceChange] Xử lý lượt đổi nguồn dở (\(journal.phase.rawValue)): \(journal.oldBookId) → \(journal.newBookId)")
        return await resolve(journal, container: container)
    }

    /// Trước mốc chốt ⇒ lùi (xoá truyện mới); sau mốc chốt ⇒ tiến (dọn truyện cũ).
    private func resolve(_ journal: BookSourceChangeJournal, container: ModelContainer) async -> RecoveryResult {
        switch journal.phase {
        case .copying:
            await rollBack(journal, container: container)
            return .rolledBack(journal)
        case .committed:
            await finishCommitted(journal, container: container)
            return .completed(journal)
        }
    }

    private func scheduleFinish(_ journal: BookSourceChangeJournal, container: ModelContainer) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: Self.finishDelayNanoseconds)
            await self.finishCommitted(journal, container: container)
            self.isRunning = false
        }
    }

    /// Xin thêm thời gian chạy khi app chuyển nền. Hết hạn ⇒ bộ chép dừng ở **giữa hai lô**, không để transaction sqlite
    /// mở lúc app bị treo (LiveContainer chế độ Shared App: giữ khoá file khi bị treo là bị hệ điều hành giết).
    private func beginBackgroundTime() {
        endBackgroundTime()
        backgroundExpired = false
        backgroundTaskId = UIApplication.shared.beginBackgroundTask(withName: "Đổi nguồn truyện") {
            MainActor.assumeIsolated {
                let coordinator = BookSourceChangeCoordinator.shared
                coordinator.backgroundExpired = true
                coordinator.endBackgroundTime()
            }
        }
    }

    private func endBackgroundTime() {
        guard backgroundTaskId != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskId)
        backgroundTaskId = .invalid
    }
}
