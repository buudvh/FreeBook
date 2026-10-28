import Foundation

/// Kết quả AI "đã xong — chưa xem" (1.3.630): lượt của truyện chạy xong (hoặc lỗi) trong lúc màn AI của truyện đó
/// **không** mở ⇒ entry ở lại `runs` với `isRunning == false` + `unseenOutcome`, nút hub giữ dòng "bấm để xem". Mở màn
/// AI của truyện bằng bất kỳ đường nào (`presentedAIBookId` nhận đúng `bookId`) là bỏ.
///
/// Lưu qua lần mở app bằng `AIUnseenResultStore`: bản ghi giữ phiên chứa kết quả (khôi phục `lastSessionIds`) và đủ
/// trường để dựng lại `ActiveContext` cho `presentFullScreen`. Nội dung chương **không** lưu (file đọc đồng bộ lúc khởi
/// tạo coordinator) ⇒ sau khi mở lại app, màn AI mở từ hub có `currentChapterRawContent` rỗng: xem kết quả không ảnh
/// hưởng, chỉ lượt chat mới từ màn đó thiếu nội dung chương. Mở qua Reader của chính truyện đó thì Reader dựng lại.
///
/// Bấm **dừng** không bao giờ tạo kết quả chưa xem: `stopActiveTask` đi thẳng `endRun`, chỉ các lối ra hoàn tất/lỗi
/// của lượt mới gọi `finishRun`.
extension AIRuntimeCoordinator {
    /// Lối ra hoàn tất/lỗi của một lượt: màn AI của truyện đang đóng ⇒ đánh dấu chưa xem (RAM + đĩa) rồi `endRun`.
    /// Gọi đúng chỗ `endRun` cũ — **sau** khi đã ghi trạng thái cuối và lưu phiên.
    func finishRun(bookId: String, outcome: AIUnseenResult.Outcome) {
        if presentedAIBookId != bookId {
            markUnseen(bookId: bookId, outcome: outcome)
        }
        endRun(bookId: bookId)
    }

    /// Màn AI của truyện vừa mở: bỏ kết quả chưa xem. Entry chỉ còn vì nó ⇒ bỏ luôn entry; còn nút "Thử lại" ⇒ chỉ
    /// xoá cờ. **Không** đụng `lastSessionIds`: `onAppear` đặt `presentedAIBookId` trước khi màn nạp phiên theo nó.
    func markResultSeen(bookId: String) {
        AIUnseenResultStore.shared.remove(bookId: bookId)
        guard let state = runs[bookId], state.unseenOutcome != nil else { return }
        if !state.isRunning, state.nameScanRetry == nil {
            runs[bookId] = nil
            pruneContexts()
        } else {
            updateRun(bookId) { $0.unseenOutcome = nil; $0.finishedAt = nil }
        }
    }

    /// Nạp lại các kết quả chưa xem của lần chạy app trước — gọi một lần trong `init`, trước mọi `pruneContexts`.
    func restoreUnseenResults() {
        for result in AIUnseenResultStore.shared.all() where runs[result.bookId] == nil {
            var state = AIBookRunState(bookId: result.bookId, bookTitle: result.bookTitle, taskTitle: "", session: nil)
            state.isRunning = false
            state.startedAt = result.finishedAt
            state.unseenOutcome = result.outcome
            state.finishedAt = result.finishedAt
            runs[result.bookId] = state
            if let sessionId = result.sessionId {
                lastSessionIds[result.bookId] = sessionId
            }
            contexts[result.bookId] = ActiveContext(
                bookId: result.bookId,
                bookTitle: result.bookTitle,
                chapterIndex: result.chapterIndex,
                chapterTitle: result.chapterTitle,
                currentChapterRawContent: "",
                translatesChapterTitles: result.translatesChapterTitles,
                convertsTraditionalToSimplified: result.convertsTraditionalToSimplified
            )
        }
    }

    /// Không có ngữ cảnh mở màn AI (không xảy ra với lượt bắt đầu từ màn AI) ⇒ không giữ: dòng hub bấm vào sẽ không
    /// mở được gì.
    private func markUnseen(bookId: String, outcome: AIUnseenResult.Outcome) {
        guard let context = contexts[bookId], let state = runs[bookId] else { return }
        let now = Date()
        updateRun(bookId) { $0.unseenOutcome = outcome; $0.finishedAt = now }
        AIUnseenResultStore.shared.upsert(AIUnseenResult(
            bookId: bookId,
            bookTitle: state.bookTitle,
            outcome: outcome,
            finishedAt: now,
            sessionId: lastSessionIds[bookId],
            chapterIndex: context.chapterIndex,
            chapterTitle: context.chapterTitle,
            translatesChapterTitles: context.translatesChapterTitles,
            convertsTraditionalToSimplified: context.convertsTraditionalToSimplified
        ))
    }
}
