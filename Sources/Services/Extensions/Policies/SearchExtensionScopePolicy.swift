import Foundation

/// Phạm vi tiện ích được duyệt/tìm ở Khám phá và Tìm kiếm — policy thuần, không I/O ngoài bảng chụp tiện ích.
///
/// - Chỉ tiện ích nội dung (`text`/`comic`/`video`) được duyệt; TTS, dịch, AI, âm thanh… bị loại.
/// - Hàng chip loại (`ExtensionKindFilterBar`) lưu lựa chọn dạng chuỗi: `""` = tất cả, còn lại là
///   `ExtensionContentKind.rawValue`. Giá trị lạ/hỏng coi như tất cả.
/// - **Đổi nguồn**: chỉ tiện ích **cùng loại** với sách (mục lục, tiến độ và chương đã tải không chuyển được
///   giữa chữ/tranh/video); hàng chip bị bỏ qua.
public enum SearchExtensionScopePolicy {
    /// Các loại hiện trên hàng chip, theo thứ tự cố định.
    public static let browsableKinds: [ExtensionContentKind] = [.text, .comic, .video]

    public static func kind(of ext: Extension) -> ExtensionContentKind {
        ExtensionContentKind(typeString: ext.type)
    }

    /// Tiện ích nội dung (chữ/tranh/video).
    public static func isBrowsable(_ ext: Extension) -> Bool {
        browsableKinds.contains(kind(of: ext))
    }

    /// Loại đang chọn trên hàng chip; `nil` = tất cả.
    public static func selectedKind(_ kindFilter: String) -> ExtensionContentKind? {
        guard let kind = ExtensionContentKind(rawValue: kindFilter), browsableKinds.contains(kind) else { return nil }
        return kind
    }

    /// `ext` có khớp lựa chọn chip không (chip "Tất cả" khớp mọi tiện ích nội dung).
    public static func matches(_ ext: Extension, kindFilter: String) -> Bool {
        guard isBrowsable(ext) else { return false }
        guard let selected = selectedKind(kindFilter) else { return true }
        return kind(of: ext) == selected
    }

    /// Danh sách nguồn để tìm. `changeSourcePackageId != nil` ⇒ đang đổi nguồn: chỉ giữ tiện ích cùng loại với
    /// sách đó và bỏ qua `kindFilter`.
    public static func searchableExtensions(
        _ extensions: [Extension],
        kindFilter: String,
        changeSourcePackageId: String?
    ) -> [Extension] {
        if let packageId = changeSourcePackageId {
            let bookKind = ExtensionContentKind.resolve(packageId: packageId)
            return extensions.filter { isBrowsable($0) && kind(of: $0) == bookKind }
        }
        return extensions.filter { matches($0, kindFilter: kindFilter) }
    }
}
