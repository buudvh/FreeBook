import SwiftUI

/// Nút thùng rác của sheet "Duyệt tên riêng & VP" **gạch** một name thay cho xoá hẳn (anh Bửu 2026-11-27: "sợ người dùng
/// lỡ tay xoá mất"). Trước đây (1.3.611–1.3.1073) nút này bỏ hẳn dòng `từ=nghĩa` khỏi tin nguồn + nhờ coordinator nhớ
/// khoá đã xoá (`AIRuntimeCoordinator.forgetName`) — lỡ tay là mất.
///
/// Nay chỉ ghi / bỏ khoá trong `AIChatMessage.struckNameKeys` của tin đó rồi lưu phiên: `content` **giữ nguyên**, sheet
/// mở lại (kể cả sau khi tắt app) đọc mảng này để vẽ hàng gạch + nút ↶ Hoàn tác; hàng gạch không chọn được nên không bao
/// giờ được lưu vào từ điển. Gạch theo từng tin (cùng name ở tin khác không bị gạch). Khoá = vế trái đã trim
/// (`AIRuntimeCoordinator.nameKey`), như cách sheet dựng danh sách từ nội dung tin.
extension ReaderAIFullScreenView {
    internal func setNameStruck(key: String, struck: Bool, inMessage messageId: UUID) {
        let target = AIRuntimeCoordinator.nameKey(key)
        guard !target.isEmpty else { return }
        guard let index = currentSession.messages.firstIndex(where: { $0.id == messageId }) else {
            AppLogger.shared.log("❌ [AI] Gạch name '\(target)': tin nguồn không còn trong phiên đang mở")
            return
        }
        var message = currentSession.messages[index]
        var keys = message.struckNameKeys ?? []
        if struck {
            guard !keys.contains(target) else { return }
            keys.append(target)
        } else {
            guard keys.contains(target) else { return }
            keys.removeAll { $0 == target }
        }
        let stored: [String]? = keys.isEmpty ? nil : keys
        message.struckNameKeys = stored
        currentSession.messages[index] = message
        AIChatHistoryStore.shared.saveSession(currentSession, for: bookId)
        // Lượt AI đang chạy giữ bản phiên riêng và ghi đè xuống đĩa khi xong / mỗi lượt quét ⇒ sửa cả bản đó, kẻo gạch
        // trong lúc đang quét / chờ AI trả lời bị mất khi mở lại (như `rememberNameEdit` của màn Sửa từ).
        AIRuntimeCoordinator.shared.updateMessage(messageId, bookId: bookId) { $0.struckNameKeys = stored }
        AppLogger.shared.log("🗑️ [AI] \(struck ? "Gạch" : "Bỏ gạch") name '\(target)' ở tin \(messageId) (còn \(keys.count) gạch)")
    }
}
