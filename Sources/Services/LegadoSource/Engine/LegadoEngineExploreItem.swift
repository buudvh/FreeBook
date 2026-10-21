import Foundation

/// Một mục của `exploreUrl` (spec §5.2, §11.2): mục bấm được (có `url`), tiêu đề nhóm (`url == nil`), hoặc **điều
/// khiển** do nguồn khai (`select`/`toggle`/`text`/`button` — chỉ gặp ở `exploreUrl` dạng JS; `type: title` là tiêu đề nhóm).
/// `url` là rule URL thô — mở mục bằng `LegadoEngineSession.fetch(url, page:)` (§5.2.3), placeholder `{{page}}` và
/// JS sinh URL được xử lý lúc đó, **không** lúc phân tích danh sách. Engine không chèn giá trị người dùng chọn vào URL:
/// giá trị đi qua `infoMap` và JS của nguồn tự sinh lại danh sách (§11.3, 0 placeholder `infoMap` trong corpus).
struct LegadoEngineExploreItem: Sendable {
    enum Kind: String, Sendable {
        /// Mục thường: ô bấm (có `url`) hoặc tiêu đề nhóm (`url == nil`).
        case link
        /// Chọn từ `chars`; đổi giá trị ⇒ ghi `infoMap[title]` rồi chạy `action`.
        case select
        /// Nút hiện phần tử hiện tại của `chars`; bấm ⇒ phần tử kế (vòng), ghi `infoMap`, chạy `action`.
        case toggle
        /// Ô nhập; ghi `infoMap[title]` khi sửa (debounce ở UI), không chạy gì.
        case text
        /// Nút chạy `action`.
        case button
    }

    var title: String
    var url: String?
    /// `style.layout_flexBasisPercent` (0…1): tỉ lệ chiều rộng ô; `nil` ⇒ mặc định.
    var flexBasisPercent: Double?
    var flexGrow: Double?
    /// `style.layout_wrapBefore`: bắt đầu hàng mới trước ô này.
    var wrapBefore: Bool
    var kind: Kind
    /// Mã JS của điều khiển (spec §11.4).
    var action: String?
    var chars: [String]
    var defaultValue: String?
    /// Nhãn hiển thị (`viewName` đã đánh giá) — mặc định = `title`.
    var label: String
    /// Giá trị hiện tại trong `infoMap` (điều khiển có giá trị); `nil` với mục thường/nút/nhãn.
    var value: String?
    var style: LegadoFlexStyle
    /// `viewName` thô (biểu thức JS) — engine đánh giá thành `label` khi dựng danh sách.
    var viewNameSource: String?

    var isGroupHeader: Bool {
        kind == .link && url == nil
    }

    /// Điều khiển do nguồn khai (không phải ô bấm/tiêu đề nhóm thường).
    var isControl: Bool {
        kind != .link
    }

    init(title: String, url: String?, flexBasisPercent: Double? = nil, flexGrow: Double? = nil, wrapBefore: Bool = false,
         kind: Kind = .link, action: String? = nil, chars: [String] = [], defaultValue: String? = nil,
         label: String? = nil, value: String? = nil, style: LegadoFlexStyle? = nil) {
        self.title = title
        self.url = url
        self.flexBasisPercent = flexBasisPercent
        self.flexGrow = flexGrow
        self.wrapBefore = wrapBefore
        self.kind = kind
        self.action = action
        self.chars = chars
        self.defaultValue = defaultValue
        self.label = label ?? title
        self.value = value
        self.style = style ?? LegadoFlexStyle(flexBasisPercent: flexBasisPercent, flexGrow: flexGrow, wrapBefore: wrapBefore)
    }

    /// `toggle`: giá trị kế tiếp (vòng) trong `chars`.
    var nextToggleValue: String {
        guard !chars.isEmpty else { return value ?? "" }
        guard let current = value, let index = chars.firstIndex(of: current) else { return chars[0] }
        return chars[(index + 1) % chars.count]
    }
}
