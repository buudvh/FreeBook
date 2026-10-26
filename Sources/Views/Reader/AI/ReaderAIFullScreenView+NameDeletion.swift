import SwiftUI

/// Nút ✕ của sheet "Duyệt tên riêng & VP" xoá **hẳn** dòng `từ=nghĩa` khỏi tin nhắn nguồn. Danh sách của sheet được
/// dựng lại từ nội dung tin mỗi lần mở (`ReaderAINameReviewSheet.loadAndDecorateNames`), nên chỉ xoá khỏi bản tạm
/// thì lần sau mở lại name vẫn hiện.
///
/// Xoá theo **khoá** (vế trái đã trim): mọi dòng trùng khoá đều đi, kể cả dòng sheet không hiện (vế phải lẫn chữ Hán)
/// — người dùng đã bảo không muốn thấy name đó nữa. Các dòng khác (kể cả dòng tiêu đề) giữ nguyên. Chỉ tin đang mở.
///
/// 1.3.611: khoá đã xoá còn được coordinator ghi nhớ theo tin (`AIRuntimeCoordinator.forgetName`) — các đường của
/// lượt quét/"Thử lại" dựng lại `content` từ danh sách tên đầy đủ lọc qua đó, nên name không quay lại. Tin cũ còn
/// `extractedNames` (dữ liệu trước đây) cũng bỏ name khỏi mảng đó: `condenseHistoricalMessages` dựng lại `content`
/// từ nó mỗi lần mở màn AI.
extension ReaderAIFullScreenView {
    internal func removeNameLine(key: String, fromMessage messageId: UUID) {
        let target = AIRuntimeCoordinator.nameKey(key)
        guard !target.isEmpty else { return }
        guard let index = currentSession.messages.firstIndex(where: { $0.id == messageId }) else {
            AppLogger.shared.log("❌ [AI] Xoá name '\(target)': tin nguồn không còn trong phiên đang mở")
            return
        }
        var message = currentSession.messages[index]
        let originalContent = message.content
        message.content = AIRuntimeCoordinator.contentRemovingNameLines(originalContent, key: target)
        let removedLines = originalContent.components(separatedBy: "\n").count
            - message.content.components(separatedBy: "\n").count
        message.extractedNames?.removeAll { AIRuntimeCoordinator.nameKey($0.original) == target }
        currentSession.messages[index] = message
        AIChatHistoryStore.shared.saveSession(currentSession, for: bookId)

        // Nhớ khoá theo tin + sửa bản phiên đang chạy + context "Thử lại" — để không đường nào dựng lại name này.
        AIRuntimeCoordinator.shared.forgetName(target, inMessage: messageId, bookId: bookId)
        batchExtractedNames.removeAll { AIRuntimeCoordinator.nameKey($0.original) == target }

        if removedLines > 0 {
            AppLogger.shared.log("🗑️ [AI] Xoá name '\(target)': bỏ \(removedLines) dòng khỏi tin \(messageId)")
        } else {
            AppLogger.shared.log("❌ [AI] Xoá name '\(target)': không thấy dòng nào trùng khoá trong tin \(messageId)")
        }
    }
}
