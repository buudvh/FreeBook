import Foundation
import SwiftData

/// Chủ luồng **lưu tiến độ đọc** của Reader, tách khỏi `ReaderViewModel` (đợt 4 tách god object, 1.3.483).
///
/// Giữ nguyên luật đã có (rules.md §5.10): chỉ ghi đĩa khi lệch ≥ 3 đoạn hoặc đổi chương, debounce **3 giây**;
/// `saveImmediately()` cho `scenePhase == .background`. `claim(.reader)` ở `start` để khi TTS đang phát,
/// TTS vẫn là chủ tiến độ (store loại snapshot `.reader` của sách đã bị `.tts` claim).
///
/// `@Published currentProgress`/`readingContext` **vẫn ở VM** (SwiftUI observe VM); coordinator chỉ đọc qua
/// `host` lúc cần, nên debounce nổ sẽ lấy vị trí **mới nhất**, đúng như code cũ đọc `self.currentProgress`.
@MainActor
final class ReaderProgressCoordinator {
    private let bookId: String
    private let store: ReadingProgressStore
    private var lastSavedProgress: ReadingProgress?
    private var dbSaveTask: Task<Void, Never>? = nil
    private weak var host: ReaderProgressHost?

    init(bookId: String, initial: ReadingProgress, store: ReadingProgressStore = .shared) {
        self.bookId = bookId
        self.lastSavedProgress = initial
        self.store = store
    }

    /// Gọi ở cuối `ReaderViewModel.init` (sau pha 1) — không được truyền closure bắt `self` vào `init` của VM.
    func attach(host: ReaderProgressHost) {
        self.host = host
    }

    /// `configure` rồi `claim(.reader)`, đúng thứ tự cũ; caller tiếp tục `ChapterContentRepository.configure` sau đó.
    func start(container: ModelContainer) async {
        await store.configure(container: container)
        await store.claim(bookId: bookId, owner: .reader)
    }

    /// Ghi snapshot RAM vào store (không chạm đĩa) — y hệt `Task { await progressStore.record(...) }` cũ.
    func record(_ progress: ReadingProgress) {
        let snapshot = progressSnapshot(progress)
        Task { await store.record(snapshot) }
    }

    func shouldScheduleSave(_ newProgress: ReadingProgress) -> Bool {
        guard ReaderProgressScheduler.shared.shouldScheduleProgressSave(bookId: bookId, chapterIndex: newProgress.chapterIndex, progressToken: 1) else { return false }
        guard let last = lastSavedProgress else { return true }
        if newProgress.chapterIndex != last.chapterIndex { return true }
        if abs(newProgress.paragraphIndex - last.paragraphIndex) >= 3 { return true }
        return false
    }

    func scheduleDebouncedSave() {
        dbSaveTask?.cancel()
        dbSaveTask = Task {
            do {
                try await Task.sleep(nanoseconds: 3 * 1_000_000_000) // Debounce 3 giây
                guard !Task.isCancelled else { return }
                await save(force: false)
            } catch {
                // Task bị hủy khi cuộn tiếp
            }
        }
    }

    func save(force: Bool = false) async {
        guard let progressToSave = host?.currentProgress else { return }
        if !force {
            guard !progressToSave.isSameLocation(as: lastSavedProgress ?? progressToSave) else { return }
        }

        do {
            await store.record(progressSnapshot(progressToSave))
            try await store.flush(bookId: bookId)
            self.lastSavedProgress = progressToSave
        } catch {
            #if DEBUG
            AppLogger.shared.log("❌ [ReaderViewModel] Lỗi ghi DB: \(error.localizedDescription)")
            #endif
        }
    }

    /// Vị trí được chụp **theo giá trị** ngay lúc gọi; Task giữ coordinator (không giữ VM) nên flush vẫn xong
    /// sau khi Reader đã đóng.
    func saveImmediately() {
        dbSaveTask?.cancel()
        dbSaveTask = nil

        guard let progressToSave = host?.currentProgress else { return }
        guard !progressToSave.isSameLocation(as: lastSavedProgress ?? progressToSave) else { return }
        let snapshot = progressSnapshot(progressToSave)

        Task(priority: .high) {
            do {
                await store.record(snapshot)
                try await store.flush(bookId: bookId)
                self.lastSavedProgress = progressToSave
            } catch {
                #if DEBUG
                AppLogger.shared.log("❌ [ReaderViewModel] Lỗi ghi đĩa khẩn cấp: \(error.localizedDescription)")
                #endif
            }
        }
    }

    func cancelPendingSave() {
        dbSaveTask?.cancel()
        dbSaveTask = nil
    }

    private func progressSnapshot(_ progress: ReadingProgress) -> ReadingProgressSnapshot {
        ReadingProgressSnapshot(
            bookId: bookId,
            chapterIndex: progress.chapterIndex,
            paragraphIndex: progress.paragraphIndex,
            chapterTitle: host?.originalChapterTitle(at: progress.chapterIndex),
            owner: .reader,
            recordedAt: Date()
        )
    }
}
