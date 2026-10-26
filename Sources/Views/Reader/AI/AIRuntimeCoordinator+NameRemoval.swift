import Foundation

/// Xoá **hẳn** một name khỏi tin kết quả (nút ✕ của sheet "Duyệt tên riêng & VP", 1.3.611).
///
/// Sửa mỗi `content` của tin là chưa đủ (lỗi của 1.3.606): ba đường của lượt quét dựng lại `content` từ **danh sách
/// tên đầy đủ** — `applyBatchProgress` mỗi lượt đang chạy, `writeNames` lúc xong / dừng vì lỗi, và nút "Thử lại k lượt
/// lỗi" (context giữ bản danh sách cũ) — nên name vừa xoá quay lại. Vì vậy khoá đã xoá được nhớ **theo tin**
/// (`removedNameKeys`) và cả ba đường lọc qua `keepingUnremovedNames` trước khi ghi; context thử lại của đúng tin đó
/// bỏ luôn name. Phạm vi là **chỉ tin đang mở** (người dùng chọn): tin kết quả khác có cùng name vẫn giữ.
extension AIRuntimeCoordinator {

    /// Khoá so khớp của một name: vế trái `từ=nghĩa` đã trim — cùng luật tách của `ReaderAINameReviewSheet`.
    nonisolated static func nameKey(_ original: String) -> String {
        original.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Bỏ mọi dòng `khoá=…` có vế trái (đã trim) bằng `key`; các dòng khác (kể cả dòng tiêu đề) giữ nguyên.
    nonisolated static func contentRemovingNameLines(_ content: String, key: String) -> String {
        content
            .components(separatedBy: "\n")
            .filter { line in
                guard let eqIdx = line.firstIndex(of: "=") else { return true }
                return nameKey(String(line[..<eqIdx])) != key
            }
            .joined(separator: "\n")
    }

    /// Ghi nhớ khoá đã xoá của tin `messageId`, sửa luôn tin đó trong phiên đang chạy (nếu có) và bỏ name khỏi
    /// context "Thử lại" khi context thuộc đúng tin này.
    func forgetName(_ key: String, inMessage messageId: UUID, bookId: String) {
        removedNameKeys[messageId, default: []].insert(key)
        updateMessage(messageId, bookId: bookId) { message in
            message.content = Self.contentRemovingNameLines(message.content, key: key)
        }
        if var context = nameScanRetryContexts[bookId], context.assistantMsgId == messageId {
            context.names.removeAll { Self.nameKey($0.original) == key }
            setNameScanRetry(context, bookId: bookId)
        }
    }

    /// Danh sách tên trước khi ghi vào tin `messageId`: bỏ các khoá người dùng đã xoá khỏi đúng tin đó.
    func keepingUnremovedNames(_ names: [AIExtractedName], messageId: UUID?) -> [AIExtractedName] {
        guard let messageId, let removed = removedNameKeys[messageId], !removed.isEmpty else { return names }
        return names.filter { !removed.contains(Self.nameKey($0.original)) }
    }
}
