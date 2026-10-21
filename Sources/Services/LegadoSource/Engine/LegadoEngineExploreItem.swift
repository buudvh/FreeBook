import Foundation

/// Một mục của `exploreUrl` (spec §5.2): mục bấm được (có `url`) hoặc tiêu đề nhóm (`url == nil`).
/// `url` là rule URL thô — mở mục bằng `LegadoEngineSession.fetch(url, page:)` (§5.2.3), placeholder `{{page}}` và
/// JS sinh URL được xử lý lúc đó, **không** lúc phân tích danh sách.
struct LegadoEngineExploreItem: Sendable {
    var title: String
    var url: String?
    /// `style.layout_flexBasisPercent` (0…1): tỉ lệ chiều rộng ô; `nil` ⇒ mặc định.
    var flexBasisPercent: Double?
    var flexGrow: Double?
    /// `style.layout_wrapBefore`: bắt đầu hàng mới trước ô này.
    var wrapBefore: Bool

    var isGroupHeader: Bool {
        url == nil
    }

    init(title: String, url: String?, flexBasisPercent: Double? = nil, flexGrow: Double? = nil, wrapBefore: Bool = false) {
        self.title = title
        self.url = url
        self.flexBasisPercent = flexBasisPercent
        self.flexGrow = flexGrow
        self.wrapBefore = wrapBefore
    }
}
