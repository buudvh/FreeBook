import SwiftUI

/// Nút bút chì của sheet "Duyệt tên riêng & VP" (1.3.780) ghi bản sửa **vào tin nguồn**, như nút ✕
/// (`+NameDeletion`): sheet dựng lại danh sách từ nội dung tin mỗi lần mở, nên chỉ sửa bản tạm thì đóng sheet là mất.
/// Tin cũ còn `extractedNames` cũng sửa theo. Coordinator nhớ lần sửa theo tin (`rememberNameEdit`) để lượt quét /
/// "Thử lại" đang dựng lại nội dung tin không đè mất. Chỉ tin đang mở.
extension ReaderAIFullScreenView {
    internal func applyNameEdit(_ edit: AINameEdit, toMessage messageId: UUID) {
        guard let index = currentSession.messages.firstIndex(where: { $0.id == messageId }) else {
            AppLogger.shared.log("❌ [AI] Sửa name: tin nguồn không còn trong phiên đang mở")
            return
        }
        var message = currentSession.messages[index]
        let originalContent = message.content
        message.content = edit.applied(toContent: originalContent)
        message.extractedNames = message.extractedNames.map { edit.applied(to: $0) }
        currentSession.messages[index] = message
        AIChatHistoryStore.shared.saveSession(currentSession, for: bookId)

        AIRuntimeCoordinator.shared.rememberNameEdit(edit, inMessage: messageId, bookId: bookId)

        // Bấm Cập nhật mà không đổi gì cũng ra cùng nội dung ⇒ không phải lỗi, chỉ ghi chú.
        let note = message.content == originalContent ? " (nội dung tin không đổi)" : ""
        AppLogger.shared.log("✏️ [AI] Sửa name '\(edit.resultingKey ?? "")' trong tin \(messageId)\(note)")
    }
}
