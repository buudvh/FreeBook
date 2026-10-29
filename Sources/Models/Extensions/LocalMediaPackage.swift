import Foundation

/// Sách **nhập từ file** dạng truyện tranh (CBZ/ZIP) và phim (MP4/MOV/M4V).
///
/// - `extensionPackageId` là một trong hai hằng dưới đây; `detailUrl`/`sourceUrl` vẫn bắt đầu bằng `local://` nên
///   `Book.isLocalBook` (và bản sao ở `BackupPayload`) vẫn đúng mà không đổi shape `@Model`.
/// - Loại nội dung suy từ packageId (`ExtensionContentKind.resolveIfKnown`), `BookContentDestination` tự chọn màn.
/// - Ảnh/phim chỉ nằm ở `ComicOfflineStore`/`VideoOfflineStore`, không có nguồn để tải lại ⇒ mọi lối "Tải offline",
///   "Xoá bản tải", "Trực tuyến", "Đổi nguồn" phải ẩn với nhóm này. Backup không gói ảnh/video (người dùng chốt) ⇒
///   khôi phục ra sách rỗng, phải nhập lại file.
public enum LocalMediaPackage {
    public static let comicPackageId = "local-comic"
    public static let videoPackageId = "local-video"

    /// `.comic`/`.video` với hai packageId ở trên, `nil` với mọi packageId khác.
    public static func contentKind(packageId: String) -> ExtensionContentKind? {
        switch packageId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case comicPackageId: return .comic
        case videoPackageId: return .video
        default: return nil
        }
    }

    public static func isLocalMedia(packageId: String?) -> Bool {
        guard let packageId else { return false }
        return contentKind(packageId: packageId) != nil
    }

    /// Chữ lỗi khi màn đọc/phát phải cần tới tiện ích nguồn. Sách nhập từ file không có nguồn — tới được đây nghĩa là
    /// file trên máy đã mất (khôi phục từ backup, hoặc bị xoá).
    public static func missingSourceMessage(packageId: String, fallback: String) -> String {
        switch contentKind(packageId: packageId) {
        case .comic: return "Ảnh của truyện này không còn trên máy — hãy nhập lại file."
        case .video: return "File phim này không còn trên máy — hãy nhập lại file."
        default: return fallback
        }
    }
}
