import Foundation

/// Phạm vi tiện ích được duyệt/tìm ở Khám phá và Tìm kiếm — policy thuần, không I/O ngoài bảng chụp tiện ích.
///
/// - Chỉ tiện ích nội dung (`text`/`comic`/`video`) được duyệt; TTS, dịch, AI, âm thanh… bị loại.
/// - Hàng chip loại (`ExtensionKindFilterBar`) lưu lựa chọn dạng chuỗi: `""` = tất cả, còn lại là
///   `ExtensionContentKind.rawValue`. Giá trị lạ/hỏng coi như tất cả.
/// - **Đổi nguồn**: chỉ tiện ích **cùng loại** với sách (mục lục, tiến độ và chương đã tải không chuyển được
///   giữa chữ/tranh/video); hàng chip bị bỏ qua. Áp cả cho "Thay đổi nguồn" ở Chi tiết truyện **chưa lưu**: khi đó
///   `changeSourcePackageId` là tiện ích của trang chi tiết (`SearchView.kindScopePackageId`).
/// - **NSFW**: tìm mọi nguồn (kể cả đổi nguồn) bỏ tiện ích NSFW khi công tắc NSFW toàn app đang tắt
///   (`RepositoryFilterPolicy.includeNsfwDefaultsKey`, mặc định tắt). Ngoại lệ: đổi nguồn cho sách của chính một
///   tiện ích NSFW thì giữ — nếu không danh sách nguồn thay thế luôn rỗng. Khám phá lọc NSFW ở chính `DiscoveryView`
///   (`matches`/`isBrowsable` ở đây không xét NSFW).
/// - **Nguồn Legado** (chung index với tiện ích JS): Khám phá dùng `isDiscoverable`, Tìm kiếm/Đổi nguồn dùng
///   `isSearchScoped` — nguồn tắt, loại không hỗ trợ hay thiếu rule không bao giờ lọt vào.
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

    /// Nguồn hiện ở Khám phá: tiện ích JS giữ nguyên luật `isBrowsable`; nguồn Legado chỉ khi chạy được và có Khám phá
    /// (`LegadoSourcePolicy.isExplorable` — đang bật, loại đã hỗ trợ, có `exploreUrl`). Nguồn Legado tắt hay thiếu
    /// `exploreUrl` vẫn là "browsable" theo loại nên phải chặn ở đây.
    public static func isDiscoverable(_ ext: Extension) -> Bool {
        guard isBrowsable(ext) else { return false }
        // Nguồn Legado không có Khám phá nhưng tìm được vẫn hiện, với danh mục tìm nhanh (`LegadoQuickSearch`).
        return !LegadoSourcePolicy.isLegado(ext) || LegadoSourcePolicy.isExplorable(ext)
            || LegadoSourcePolicy.isQuickSearchable(ext)
    }

    /// Nguồn được tìm (kể cả đổi nguồn): tiện ích JS giữ nguyên; nguồn Legado chỉ khi chạy được và có rule tìm kiếm
    /// (`LegadoSourcePolicy.isSearchable`).
    public static func isSearchScoped(_ ext: Extension) -> Bool {
        !LegadoSourcePolicy.isLegado(ext) || LegadoSourcePolicy.isSearchable(ext)
    }

    /// `ext` có khớp lựa chọn chip không (chip "Tất cả" khớp mọi tiện ích nội dung).
    public static func matches(_ ext: Extension, kindFilter: String) -> Bool {
        guard isBrowsable(ext) else { return false }
        guard let selected = selectedKind(kindFilter) else { return true }
        return kind(of: ext) == selected
    }

    /// Danh sách nguồn để tìm. `changeSourcePackageId != nil` ⇒ đang đổi nguồn: chỉ giữ tiện ích cùng loại với
    /// sách đó và bỏ qua `kindFilter`. Không tra được loại của sách (tiện ích đã gỡ, không còn trong catalog) ⇒
    /// giữ mọi tiện ích nội dung thay vì đoán là chữ.
    ///
    /// `includeNsfw` mặc định đọc công tắc NSFW của bộ lọc Kho ngay lúc gọi (call site không đổi).
    public static func searchableExtensions(
        _ extensions: [Extension],
        kindFilter: String,
        changeSourcePackageId: String?,
        includeNsfw: Bool = RepositoryFilterPolicy.includesNsfwPreference
    ) -> [Extension] {
        // Bỏ nguồn Legado không tìm được **trước** khi lọc loại/NSFW: hàng nghìn bản ghi Legado tắt không phải đi qua
        // bộ phân loại NSFW mỗi lượt vẽ.
        let candidates = extensions.filter { isSearchScoped($0) }
        let scoped: [Extension]
        if let packageId = changeSourcePackageId {
            if let bookKind = ExtensionContentKind.resolveIfKnown(packageId: packageId) {
                scoped = candidates.filter { isBrowsable($0) && kind(of: $0) == bookKind }
            } else {
                scoped = candidates.filter { isBrowsable($0) }
            }
        } else {
            scoped = candidates.filter { matches($0, kindFilter: kindFilter) }
        }
        let keeps = keepsNsfw(changeSourcePackageId: changeSourcePackageId, includeNsfw: includeNsfw)
        return RepositoryFilterPolicy.applyNsfwFilter(scoped, includeNsfw: keeps)
    }

    /// Có giữ nguồn NSFW trong lượt tìm không: công tắc bật, hoặc đang đổi nguồn cho sách của chính một nguồn NSFW
    /// (người dùng giữ ngoại lệ này 2026-10-24). Đọc được từ thread bất kỳ — `LegadoSearchScheduler` xét lại trước
    /// khi chạy nguồn Legado đang xếp hàng.
    public static func keepsNsfw(
        changeSourcePackageId: String?,
        includeNsfw: Bool = RepositoryFilterPolicy.includesNsfwPreference
    ) -> Bool {
        includeNsfw || (changeSourcePackageId.map { RepositoryFilterPolicy.isNsfwSource(packageId: $0) } ?? false)
    }
}
