import Foundation

enum ChapterPersistenceError: LocalizedError {
    case unavailableStore
    case missingBook(bookId: String)
    case invalidContent
    case writeFailed(key: String)

    var errorDescription: String? {
        switch self {
        case .unavailableStore:
            return "Cơ sở dữ liệu cục bộ chưa sẵn sàng"
        case .missingBook(let bookId):
            return "Không tìm thấy sách \(bookId) để lưu chương"
        case .invalidContent:
            return "Nội dung chương không hợp lệ"
        case .writeFailed(let key):
            return "Lưu chương thất bại cho key: \(key)"
        }
    }
}
