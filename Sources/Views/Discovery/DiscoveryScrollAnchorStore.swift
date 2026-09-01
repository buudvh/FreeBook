import Foundation

/// Ghi nhớ vị trí cuộn của từng tab danh mục ở Khám Phá.
///
/// Tồn tại vì `TabView(.page)` được `UIPageViewController` dựng lại trang khi trang đó rời vùng lân
/// cận, và **cửa sổ ±3 tab** của `DiscoveryView` còn xoá hẳn tab đi xa hơn — cả hai đường đều làm mất
/// offset của `List` dù dữ liệu đã nạp vẫn còn. Đổi tab rồi về thì người dùng phải cuộn lại từ đầu.
///
/// Neo là **`link` của truyện đang ở trên cùng viewport**, không phải `CGFloat` offset (chiều cao hàng
/// phụ thuộc bìa/tên nên offset không tái lập được sau một lượt dựng lại) và cũng không phải
/// `ExtensionItemResult.id` — id đó là `UUID()` mới mỗi lần bóc tách, nên sau một lượt nạp lại nó không
/// còn khớp và neo thành vô dụng. `link` là định danh nội dung, ổn định qua nạp lại.
///
/// Là `class` giữ trong `@State` (không `@StateObject`, không `@Published`) theo đúng khuôn
/// `ParagraphTracker`: mỗi hàng xuất hiện/biến mất ghi vào đây, và **không lượt nào được phép**
/// invalidate body của tab — nếu không thì cuộn một danh sách dài sẽ dựng lại cả cây view mỗi hàng.
@MainActor
public final class DiscoveryScrollAnchorStore {
    private var anchors: [String: String] = [:]
    private var visible: [String: Set<String>] = [:]

    public init() {}

    // MARK: - Hàng đang hiện

    public func setVisible(_ novelId: String, isVisible: Bool, categoryId: String) {
        guard !categoryId.isEmpty, !novelId.isEmpty else { return }
        if isVisible {
            visible[categoryId, default: []].insert(novelId)
        } else {
            visible[categoryId]?.remove(novelId)
        }
    }

    public func isVisible(_ novelId: String, categoryId: String) -> Bool {
        visible[categoryId]?.contains(novelId) ?? false
    }

    public func hasVisibleRows(categoryId: String) -> Bool {
        !(visible[categoryId]?.isEmpty ?? true)
    }

    // MARK: - Neo

    /// Gọi **một lần mỗi lượt rời tab**, không gọi theo từng hàng: `orderedIds` là danh sách đầy đủ nên
    /// đây là phép quét O(n), chỉ đáng trả một lần cho mỗi lần đổi tab.
    public func captureAnchor(categoryId: String, orderedIds: [String]) {
        guard let topmost = orderedIds.first(where: { isVisible($0, categoryId: categoryId) }) else { return }
        anchors[categoryId] = topmost
    }

    public func anchor(for categoryId: String) -> String? {
        anchors[categoryId]
    }

    /// Đổi nguồn hoặc nạp lại danh mục ⇒ mọi neo cũ trỏ vào danh sách không còn tồn tại.
    public func removeAll() {
        anchors.removeAll()
        visible.removeAll()
    }
}
