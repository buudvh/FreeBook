import Foundation

/// Lọc ba nhóm của `ShelfBookPartition` (ghim / chưa ghim / lịch sử) theo chip loại nội dung của Kệ sách + Lịch sử
/// (`@AppStorage("shelfKindFilter")`, giá trị như `ExtensionKindFilterBar`: `""` = tất cả).
///
/// Thuần, chạy mỗi body của `ShelfView` ngay sau partition: loại của sách suy ra **lúc chạy** từ tiện ích nguồn
/// (`ExtensionContentKind.resolve(packageId:)`, `Book` không lưu loại), nên nhớ theo `packageId` để mỗi nguồn chỉ
/// tra một lần — cùng cách `ShelfBookPartition` nhớ kết quả NSFW.
///
/// Thanh chip chỉ hiện khi kệ ∪ lịch sử (đã lọc NSFW) có từ 2 loại trở lên. Thanh ẩn ⇒ lựa chọn đã lưu bị **bỏ
/// qua** (coi như "Tất cả"), nếu không một lựa chọn cũ như "Truyện tranh" trên kệ chỉ còn truyện chữ sẽ cho ra kệ
/// rỗng mà không có chip nào để thoát.
struct ShelfKindFilter {
    private(set) var pinned: [Book]
    private(set) var unpinned: [Book]
    private(set) var history: [Book]
    /// Các loại có mặt trên kệ ∪ lịch sử. `.unsupported` gộp vào `.text`, giống `BookListLayoutScope(kind:)`.
    let presentKinds: Set<ExtensionContentKind>
    /// Loại đang lọc; `nil` = "Tất cả" (kể cả khi thanh chip ẩn).
    let selectedKind: ExtensionContentKind?

    var showsFilterBar: Bool { presentKinds.count >= 2 }

    /// Phạm vi kiểu hiển thị: loại của chip đang chọn, hoặc "Tất cả".
    var scope: BookListLayoutScope {
        selectedKind.map { BookListLayoutScope(kind: $0) } ?? .all
    }

    var isShelfEmpty: Bool { pinned.isEmpty && unpinned.isEmpty }

    init(_ parts: ShelfBookPartition, kindFilter: String) {
        var kindByPackageId: [String: ExtensionContentKind] = [:]
        var kinds = Set<ExtensionContentKind>()
        for group in [parts.pinned, parts.unpinned, parts.history] {
            for book in group {
                kinds.insert(Self.kind(of: book, cache: &kindByPackageId))
            }
        }
        presentKinds = kinds

        let stored = SearchExtensionScopePolicy.selectedKind(kindFilter).map(Self.normalized)
        let selected = kinds.count >= 2 ? stored : nil
        selectedKind = selected

        guard let selected else {
            pinned = parts.pinned
            unpinned = parts.unpinned
            history = parts.history
            return
        }
        // Mọi `packageId` đã nằm trong cache sau vòng trên ⇒ lọc không tra kho thêm lần nào.
        pinned = parts.pinned.filter { Self.kind(of: $0, cache: &kindByPackageId) == selected }
        unpinned = parts.unpinned.filter { Self.kind(of: $0, cache: &kindByPackageId) == selected }
        history = parts.history.filter { Self.kind(of: $0, cache: &kindByPackageId) == selected }
    }

    private static func kind(of book: Book, cache: inout [String: ExtensionContentKind]) -> ExtensionContentKind {
        let packageId = book.extensionPackageId
        if let cached = cache[packageId] {
            return cached
        }
        let resolved = normalized(ExtensionContentKind.resolve(packageId: packageId))
        cache[packageId] = resolved
        return resolved
    }

    private static func normalized(_ kind: ExtensionContentKind) -> ExtensionContentKind {
        kind == .unsupported ? .text : kind
    }
}
