import Foundation

enum ReaderLoadError: LocalizedError {
    case noChapters
    case invalidChapterIndex(Int, total: Int)
    case missingChapterSnapshot(Int)
    case missingExtension
    case timedOut

    var errorDescription: String? {
        switch self {
        case .noChapters:
            return "Không tìm thấy chương để đọc"
        case .invalidChapterIndex(let index, let total):
            return "Chương \(index + 1) nằm ngoài danh sách \(total) chương"
        case .missingChapterSnapshot(let index):
            return "Chưa có dữ liệu cho chương \(index + 1)"
        case .missingExtension:
            return "Không tìm thấy tiện ích bóc tách"
        case .timedOut:
            return "Tải chương quá thời gian cho phép"
        }
    }
}
