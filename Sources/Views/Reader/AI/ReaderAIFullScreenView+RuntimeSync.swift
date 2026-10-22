import SwiftUI

/// Đồng bộ màn AI với trạng thái chạy của **chính truyện này** trong `AIRuntimeCoordinator.runs` (1.3.558).
///
/// Trước 1.3.558 màn nghe thẳng các cờ toàn cục (`isRunning`, `batchProgress`…) nên quét truyện A thì màn AI của
/// truyện B cũng hiện dải quét và bị khoá. Nay chỉ đọc `runs[bookId]`: `nil` = truyện này không chạy gì.
///
/// `runs` phát mỗi ≥ 50 ms khi **bất kỳ** truyện nào đang stream ⇒ mọi phép gán ở đây chỉ chạy khi giá trị thật sự
/// đổi, để màn của truyện B không vẽ lại theo nhịp chữ của truyện A.
extension ReaderAIFullScreenView {
    internal func applyRunState(_ run: AIBookRunState?) {
        let running = run?.isRunning ?? false
        if isStreaming != running {
            isStreaming = running
        }
        let progress = run?.batchProgress
        if batchProgress != progress {
            batchProgress = progress
        }
        if isBatchExtracting != (progress != nil) {
            isBatchExtracting = (progress != nil)
        }
        if let names = run?.batchExtractedNames, !names.isEmpty, names != batchExtractedNames {
            batchExtractedNames = names
        }
        if nameScanRetry != run?.nameScanRetry {
            nameScanRetry = run?.nameScanRetry
        }
        if let updated = run?.session, updated.id == currentSession.id {
            mergeRunningSession(updated)
        }
    }

    /// Gộp tin của phiên đang chạy vào phiên đang hiển thị: sửa tin đã có (nội dung, trạng thái chạy, tên riêng),
    /// thêm tin mới — không bỏ tin nào màn đang có.
    private func mergeRunningSession(_ updated: AIChatSession) {
        for updatedMsg in updated.messages {
            if let idx = currentSession.messages.firstIndex(where: { $0.id == updatedMsg.id }) {
                if currentSession.messages[idx].content != updatedMsg.content ||
                   currentSession.messages[idx].isStreaming != updatedMsg.isStreaming ||
                   currentSession.messages[idx].extractedNames?.count != updatedMsg.extractedNames?.count {
                    currentSession.messages[idx].content = updatedMsg.content
                    currentSession.messages[idx].isStreaming = updatedMsg.isStreaming
                    currentSession.messages[idx].extractedNames = updatedMsg.extractedNames
                }
            } else {
                currentSession.messages.append(updatedMsg)
            }
        }
    }
}
