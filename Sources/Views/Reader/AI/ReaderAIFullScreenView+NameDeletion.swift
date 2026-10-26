import SwiftUI

/// Nút ✕ của sheet "Duyệt tên riêng & VP" xoá **hẳn** dòng `từ=nghĩa` khỏi tin nhắn nguồn. Danh sách của sheet được
/// dựng lại từ nội dung tin mỗi lần mở (`ReaderAINameReviewSheet.loadAndDecorateNames`), nên chỉ xoá khỏi bản tạm
/// thì lần sau mở lại name vẫn hiện.
///
/// Xoá theo **khoá** (vế trái đã trim): mọi dòng trùng khoá đều đi, kể cả dòng sheet không hiện (vế phải lẫn chữ Hán)
/// — người dùng đã bảo không muốn thấy name đó nữa. Các dòng khác (kể cả dòng tiêu đề) giữ nguyên.
extension ReaderAIFullScreenView {
    internal func removeNameLine(key: String, fromMessage messageId: UUID) {
        let target = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else { return }
        guard let index = currentSession.messages.firstIndex(where: { $0.id == messageId }) else {
            AppLogger.shared.log("[AI] Xoá name '\(target)': tin nguồn không còn trong phiên đang mở")
            return
        }
        let original = currentSession.messages[index].content
        let updated = Self.contentRemovingNameLines(original, key: target)
        guard updated != original else { return }
        currentSession.messages[index].content = updated
        AIChatHistoryStore.shared.saveSession(currentSession, for: bookId)

        // Truyện đang chạy AI: `mergeRunningSession` chép nội dung từ phiên của coordinator đè lên tin đang hiển thị
        // ⇒ sửa luôn bản đó, không thì dòng vừa xoá quay lại ở nhịp đồng bộ kế tiếp.
        AIRuntimeCoordinator.shared.updateMessage(messageId, bookId: bookId) { message in
            message.content = Self.contentRemovingNameLines(message.content, key: target)
        }
    }

    /// Bỏ mọi dòng `khoá=…` có vế trái (đã trim) bằng `key`; cùng luật tách `từ=nghĩa` với `ReaderAINameReviewSheet`.
    nonisolated static func contentRemovingNameLines(_ content: String, key: String) -> String {
        content
            .components(separatedBy: "\n")
            .filter { line in
                guard let eqIdx = line.firstIndex(of: "=") else { return true }
                return line[..<eqIdx].trimmingCharacters(in: .whitespacesAndNewlines) != key
            }
            .joined(separator: "\n")
    }
}
