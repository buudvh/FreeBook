import Combine
import Foundation

/// Chữ của sheet điều khiển nhanh TTS (`TTSQuickControlSheet`; có từ kiểu Thanh nghe nhạc 1.3.796, thanh bỏ ở 1.3.808): dòng 1
/// tên truyện, dòng 2 tên chương (1.3.804 bỏ tiền tố "Ch. N"). Lấy từ
/// `TTSManager.displayedBookTitle` / `displayedChapterTitle` (đã dịch theo phiên TTS) — hai hàm này dịch **đồng bộ** nên chỉ
/// tính lại khi (truyện, chương, tên thô) đổi hoặc từ điển vừa cập nhật, không theo từng đoạn / từng giây hẹn giờ.
///
/// `bookTitle` / `chapterTitle` của manager không `@Published` ⇒ đọc ở lượt sau (`receive(on:)`) của các tín hiệu có phát.
///
/// Có chương trước / chương kế trong hàng đợi (`hasPreviousChapter` / `hasNextChapter`, 2026-11-11) cho hai nút chương ở
/// hai đầu hàng nút của sheet — tính lại khi đổi chương và khi hàng đợi chương đổi (lúc đầu chỉ vài chương, ~1 s sau mới đủ).
@MainActor
final class TTSWidgetBarInfoReader: ObservableObject {
    @Published private(set) var bookTitle = ""
    @Published private(set) var chapterLine = ""
    @Published private(set) var hasPreviousChapter = false
    @Published private(set) var hasNextChapter = false

    private struct Key: Equatable {
        let bookId: String
        let chapterIndex: Int
        let rawBookTitle: String
        let rawChapterTitle: String
    }

    private var lastKey: Key?
    private var cancellables = Set<AnyCancellable>()

    init(manager: TTSManager? = nil) {
        let manager = manager ?? TTSManager.shared
        refresh(from: manager)

        manager.$playingBookId.map { _ in () }.receive(on: RunLoop.main).sink { [weak self, weak manager] in
            self?.refresh(from: manager)
        }.store(in: &cancellables)
        manager.$playingChapterIndex.map { _ in () }.receive(on: RunLoop.main).sink { [weak self, weak manager] in
            self?.refresh(from: manager)
        }.store(in: &cancellables)
        // Tên chương thô có thể được gán sau chỉ số chương; bắt đầu/dừng phát là lúc chắc chắn đã gán xong.
        manager.$isPlaying.map { _ in () }.receive(on: RunLoop.main).sink { [weak self, weak manager] in
            self?.refresh(from: manager)
        }.store(in: &cancellables)
        manager.$chaptersQueue.map(\.count).removeDuplicates().map { _ in () }.receive(on: RunLoop.main)
            .sink { [weak self, weak manager] in
                self?.refreshAdjacentChapters(from: manager)
            }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: .translationDictionariesDidUpdate)
            .receive(on: RunLoop.main)
            .sink { [weak self, weak manager] _ in
                self?.lastKey = nil
                self?.refresh(from: manager)
            }
            .store(in: &cancellables)
    }

    private func refresh(from manager: TTSManager?) {
        guard let manager else { return }
        refreshAdjacentChapters(from: manager)
        let key = Key(
            bookId: manager.playingBookId,
            chapterIndex: manager.playingChapterIndex,
            rawBookTitle: manager.bookTitle,
            rawChapterTitle: manager.chapterTitle
        )
        guard key != lastKey else { return }
        lastKey = key

        let title = manager.displayedBookTitle
        if title != bookTitle { bookTitle = title }

        // Chỉ tên chương, không thêm "Ch. N" phía trước (1.3.804, anh Bửu). Tên rỗng mới lùi về "Chương N".
        let chapter = manager.displayedChapterTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let index = manager.playingChapterIndex
        let line = chapter.isEmpty && index >= 0 ? "Chương \(index + 1)" : chapter
        if line != chapterLine { chapterLine = line }
    }

    private func refreshAdjacentChapters(from manager: TTSManager?) {
        guard let manager else { return }
        let index = manager.playingChapterIndex
        let hasPrevious = index >= 0 && manager.previousChapterIndex(before: index) != nil
        let hasNext = index >= 0 && manager.nextChapterIndex(after: index) != nil
        if hasPrevious != hasPreviousChapter { hasPreviousChapter = hasPrevious }
        if hasNext != hasNextChapter { hasNextChapter = hasNext }
    }
}
