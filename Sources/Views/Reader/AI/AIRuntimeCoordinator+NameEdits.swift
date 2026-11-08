import Foundation

/// Sửa name trong tin kết quả bằng nút bút chì của sheet "Duyệt tên riêng & VP" (1.3.780) — cùng lý do với
/// `+NameRemoval`: `applyBatchProgress` (mỗi nhịp của lượt đang chạy), `writeNames` (lúc xong / dừng vì lỗi) và nút
/// "Thử lại k lượt lỗi" dựng lại `content` từ **danh sách tên đầy đủ**, nên chỉ sửa `content` thì bản sửa mất ở nhịp
/// sau. Vì vậy mỗi lần sửa được nhớ **theo tin** (`nameEdits`) và hai hàm ghi áp lại cả chuỗi sửa, đúng thứ tự, sau
/// bộ lọc khoá đã ✕ (`applyingUserNameChanges`); context thử lại của đúng tin đó sửa luôn. Phạm vi chỉ tin đang mở.
extension AIRuntimeCoordinator {

    /// Ghi nhớ lần sửa của tin `messageId`, sửa luôn tin đó trong phiên đang chạy (nếu có) và danh sách của context
    /// "Thử lại" khi context thuộc đúng tin này.
    func rememberNameEdit(_ edit: AINameEdit, inMessage messageId: UUID, bookId: String) {
        nameEdits[messageId, default: []].append(edit)
        updateMessage(messageId, bookId: bookId) { message in
            message.content = edit.applied(toContent: message.content)
            message.extractedNames = message.extractedNames.map { edit.applied(to: $0) }
        }
        if var context = nameScanRetryContexts[bookId], context.assistantMsgId == messageId {
            context.names = edit.applied(to: context.names)
            setNameScanRetry(context, bookId: bookId)
        }
    }

    /// Danh sách tên trước khi ghi vào tin `messageId`: bỏ các khoá người dùng đã ✕, rồi áp lại các lần sửa.
    func applyingUserNameChanges(_ names: [AIExtractedName], messageId: UUID?) -> [AIExtractedName] {
        let kept = keepingUnremovedNames(names, messageId: messageId)
        guard let messageId, let edits = nameEdits[messageId], !edits.isEmpty else { return kept }
        return edits.reduce(kept) { list, edit in edit.applied(to: list) }
    }
}
