import Foundation

/// Vòng đời một lượt AI **theo truyện** (1.3.558): mở lượt, so mã lượt cho mọi cập nhật trễ, sửa tin trong phiên đang
/// chạy, kết thúc lượt, dừng theo yêu cầu người dùng, toast kèm tên truyện.
///
/// Mọi hàm chỉ chạm entry của **đúng** `bookId` được truyền vào: lệnh mới của truyện nào chỉ thay tác vụ cũ của chính
/// truyện đó, bấm dừng ở truyện B không bao giờ huỷ lượt quét của truyện A.
extension AIRuntimeCoordinator {
    /// Trạng thái AI hiện tại của một truyện; `nil` = truyện không chạy gì.
    public func run(for bookId: String) -> AIBookRunState? {
        runs[bookId]
    }

    /// Phiên chat mà lượt gần nhất của truyện đã dùng — màn AI mở lại đúng phiên đó sau khi lượt kết thúc.
    public func lastSessionId(for bookId: String) -> UUID? {
        lastSessionIds[bookId]
    }

    /// Mở một lượt mới cho truyện: huỷ tác vụ cũ **của chính truyện đó**, dựng entry mới (giữ nút "Thử lại" nếu có),
    /// cấp mã lượt. Mọi cập nhật trễ của lượt phải so mã này qua `isCurrentRun`. Lượt mới thay kết quả chưa xem của
    /// lượt trước (1.3.630) — entry mới không mang cờ đó, bản ghi trên đĩa cũng bỏ.
    func beginRun(bookId: String, bookTitle: String, taskTitle: String, session: AIChatSession?) -> UUID {
        cancelTask(bookId: bookId)
        AIUnseenResultStore.shared.remove(bookId: bookId)
        var state = AIBookRunState(bookId: bookId, bookTitle: bookTitle, taskTitle: taskTitle, session: session)
        state.nameScanRetry = runs[bookId]?.nameScanRetry
        runs[bookId] = state
        if let session {
            lastSessionIds[bookId] = session.id
        }
        let runId = UUID()
        runIds[bookId] = runId
        return runId
    }

    /// Lượt `runId` vẫn là lượt hiện hành của truyện — chưa bị dừng hay bị lệnh mới của chính truyện đó thay.
    func isCurrentRun(_ runId: UUID, bookId: String) -> Bool {
        runIds[bookId] == runId
    }

    /// Sửa entry của truyện trong **một** lần ghi (một lần phát `runs`). Truyện không có entry ⇒ bỏ qua.
    func updateRun(_ bookId: String, _ body: (inout AIBookRunState) -> Void) {
        guard var state = runs[bookId] else { return }
        body(&state)
        runs[bookId] = state
    }

    /// Sửa một tin trong phiên đang chạy của truyện (không có phiên / không có tin ⇒ bỏ qua).
    func updateMessage(_ messageId: UUID?, bookId: String, _ body: (inout AIChatMessage) -> Void) {
        guard let messageId else { return }
        updateRun(bookId) { state in
            guard var session = state.session,
                  let index = session.messages.firstIndex(where: { $0.id == messageId }) else { return }
            body(&session.messages[index])
            state.session = session
        }
    }

    /// Ghi phiên đang chạy của truyện xuống lịch sử chat.
    func saveRunSession(bookId: String) {
        guard let session = runs[bookId]?.session else { return }
        AIChatHistoryStore.shared.saveSession(session, for: bookId)
    }

    /// Huỷ tác vụ đang bay của **một** truyện — không đụng tin nhắn, không đụng entry, không đụng truyện khác.
    func cancelTask(bookId: String) {
        runIds[bookId] = nil
        tasks.removeValue(forKey: bookId)?.cancel()
    }

    /// Kết thúc lượt của truyện (xong, lỗi hoặc dừng): bỏ entry để màn AI và nút nổi thấy truyện đã rảnh. Còn lượt
    /// quét lỗi chờ nút "Thử lại", hoặc kết quả chưa xem (`finishRun` đã gắn `unseenOutcome`, 1.3.630), thì giữ entry
    /// nhưng `isRunning = false` và bỏ `session` (đã ghi xuống lịch sử).
    ///
    /// Gọi **sau** khi đã ghi trạng thái cuối của phiên vào entry: màn AI đang mở nhận bản cuối đó trước khi entry mất.
    /// Lối ra hoàn tất/lỗi đi qua `finishRun`; bấm dừng gọi thẳng hàm này nên không bao giờ thành kết quả chưa xem.
    func endRun(bookId: String) {
        runIds[bookId] = nil
        tasks[bookId] = nil
        if var state = runs[bookId], state.nameScanRetry != nil || state.unseenOutcome != nil {
            state.isRunning = false
            state.session = nil
            state.batchProgress = nil
            state.batchExtractedNames = []
            runs[bookId] = state
        } else {
            runs[bookId] = nil
        }
        pruneContexts()
    }

    /// Người dùng bấm **dừng** trong màn AI của truyện (1.3.515): huỷ tác vụ của truyện đó, hoàn tất mọi tin đang chạy
    /// trong phiên — tin còn rỗng ghi "Đã dừng." — rồi lưu phiên. Không làm vậy thì luồng bị huỷ thoát mà tin vẫn
    /// `isStreaming`, màn AI đồng bộ ngược trạng thái đó nên dòng "AI đang suy nghĩ" không bao giờ mất.
    ///
    /// Đang lọc name nhiều chương (lần quét hoặc thử lại — entry có `batchProgress`) ⇒ toast "Đã dừng lọc name" kèm
    /// chương của lượt đang gửi, kể cả khi màn AI đang mở. Đọc tiến độ **trước** khi huỷ/`endRun` dọn entry; chat thường
    /// không có tiến độ ⇒ không toast.
    public func stopActiveTask(bookId: String) {
        let stopToast: String? = runs[bookId]?.batchProgress == nil
            ? nil
            : nameScanStopToast("Đã dừng lọc name", bookId: bookId, bookTitle: runs[bookId]?.bookTitle ?? "")
        cancelTask(bookId: bookId)
        updateRun(bookId) { state in
            guard var session = state.session else { return }
            for index in session.messages.indices where session.messages[index].isStreaming {
                session.messages[index].isStreaming = false
                if session.messages[index].content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    session.messages[index].content = "Đã dừng."
                }
            }
            state.session = session
        }
        saveRunSession(bookId: bookId)
        endRun(bookId: bookId)
        if let stopToast {
            ToastManager.shared.show(message: stopToast, type: .info)
        }
    }

    /// Chữ toast của một truyện: màn AI của truyện đó không mở (đang ở màn khác hoặc màn AI của truyện khác) ⇒ kèm
    /// tên truyện để người dùng biết toast nói về truyện nào.
    func toastText(_ message: String, bookId: String, bookTitle: String) -> String {
        guard presentedAIBookId != bookId, !bookTitle.isEmpty else { return message }
        return "\(message) · \(bookTitle)"
    }
}
