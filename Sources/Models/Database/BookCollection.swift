import Foundation
import SwiftData

/// Bộ sưu tập sách do người dùng tự tạo. Quan hệ với `Book` là **N-N**: một truyện nằm trong nhiều bộ,
/// một bộ chứa nhiều truyện.
///
/// `deleteRule: .nullify` là **bắt buộc** ở đây: xoá một bộ sưu tập chỉ được tháo liên kết, tuyệt đối
/// không kéo theo `Book` — truyện vẫn phải nằm trên kệ. Đổi thành `.cascade` là xoá sách thật.
///
/// Chiều nghịch khai ở phía bộ sưu tập (giống `Repository.extensions` ⇄ `Extension.repository`), nên
/// `Book.collections` để trơn không macro.
@Model
public final class BookCollection {
    @Attribute(.unique) public var collectionId: String
    public var name: String
    /// Thứ tự người dùng thấy trong tab Bộ sưu tập. Bộ mới luôn xuống cuối.
    public var sortOrder: Int = 0
    public var createdAt: Date = Date()

    @Relationship(deleteRule: .nullify, inverse: \Book.collections)
    public var books: [Book] = []

    public init(
        collectionId: String = UUID().uuidString,
        name: String,
        sortOrder: Int = 0,
        createdAt: Date = Date()
    ) {
        self.collectionId = collectionId
        self.name = name
        self.sortOrder = sortOrder
        self.createdAt = createdAt
    }
}

extension BookCollection: Identifiable {
    public var id: String { collectionId }
}
