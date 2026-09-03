import Foundation

public enum BookTransactionError: LocalizedError {
    case saveFailed(String)
    case bookNotFound(String)
    case collectionNotFound(String)
    case invalidCollectionName
    case duplicateCollectionName(String)

    public var errorDescription: String? {
        switch self {
        case .saveFailed(let msg): return "Lưu thông tin sách thất bại: \(msg)"
        case .bookNotFound(let id): return "Không tìm thấy sách: \(id)"
        case .collectionNotFound(let id): return "Không tìm thấy bộ sưu tập: \(id)"
        case .invalidCollectionName: return "Tên bộ sưu tập không được để trống"
        case .duplicateCollectionName(let name): return "Đã có bộ sưu tập tên '\(name)'"
        }
    }
}
