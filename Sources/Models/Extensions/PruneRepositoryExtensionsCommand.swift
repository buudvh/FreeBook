import Foundation

/// Lệnh dọn các bản ghi tiện ích **không còn nằm trong registry** của một kho.
///
/// `keepPackageIds` là tập `packageId` mà lần đồng bộ vừa rồi **thật sự đọc được** từ `plugin.json`
/// của kho — không phải tập mong muốn, mà tập đã tải về thành công. Mọi tiện ích thuộc kho mà không
/// có trong tập này được coi là đã bị tác giả kho gỡ khỏi danh sách.
///
/// Hai lằn ranh an toàn cố ý:
/// - Tiện ích **đã cài** (`localPath` khác rỗng) luôn được giữ, kể cả khi kho đã gỡ nó: file JS cục bộ
///   vẫn còn và truyện trong tủ vẫn đang trỏ tới nguồn đó.
/// - `keepPackageIds` rỗng được coi là "không có dữ liệu để so", tức **không xoá gì**. Nhờ vậy một
///   lần fetch trả về danh sách rỗng (kho lỗi, mạng trả file trắng) không quét sạch cả kho.
public struct PruneRepositoryExtensionsCommand: Sendable {
    public let repositoryUrl: String
    public let keepPackageIds: Set<String>

    public init(repositoryUrl: String, keepPackageIds: Set<String>) {
        self.repositoryUrl = repositoryUrl
        self.keepPackageIds = keepPackageIds
    }
}
