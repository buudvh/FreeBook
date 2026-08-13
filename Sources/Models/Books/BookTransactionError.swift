import Foundation

public enum BookTransactionError: LocalizedError {
    case saveFailed(String)
    case bookNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .saveFailed(let msg): return "Lưu thông tin sách thất bại: \(msg)"
        case .bookNotFound(let id): return "Không tìm thấy sách: \(id)"
        }
    }
}
