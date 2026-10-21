import Foundation

/// Yêu cầu nhập mã xác minh (`java.getVerificationCode(imageUrl)`, spec §10.8): ảnh đã được engine tải bằng client
/// của nguồn (cùng phiên cookie). Presenter trả mã bằng `completeVerification(id:code:)` (`nil` = huỷ ⇒ JS nhận `""`).
struct LegadoVerificationRequest: Sendable, Identifiable {
    let id: UUID
    let sourceKey: String
    let sourceName: String
    let imageURL: String
    /// Byte ảnh (PNG/JPEG/GIF/SVG…); `nil` khi tải ảnh lỗi — vẫn hỏi để người dùng có thể huỷ.
    let imageData: Data?
    let imageMimeType: String?
}
