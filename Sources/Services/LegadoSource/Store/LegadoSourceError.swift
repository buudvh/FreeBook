import Foundation

/// Lỗi của kho nguồn Legado (nhập, ghi/đọc file, bật/tắt, xoá). Thông báo tiếng Việt để View hiện thẳng.
public enum LegadoSourceError: LocalizedError, Sendable, Equatable {
    case emptyInput
    case invalidJSON
    case noSourcesFound
    case invalidURL(String)
    case network(String)
    case httpStatus(Int)
    case responseTooLarge
    case fileRead(String)
    case fileWrite(String)
    case notFound(String)
    case unsafePath
    case index(String)

    public var errorDescription: String? {
        switch self {
        case .emptyInput:
            return "Không có dữ liệu để nhập."
        case .invalidJSON:
            return "Nội dung không phải JSON nguồn Legado hợp lệ."
        case .noSourcesFound:
            return "Không tìm thấy nguồn nào trong dữ liệu."
        case .invalidURL(let url):
            return "URL không hợp lệ: \(url)"
        case .network(let message):
            return "Lỗi tải dữ liệu: \(message)"
        case .httpStatus(let code):
            return "Máy chủ trả mã lỗi HTTP \(code)."
        case .responseTooLarge:
            return "Tệp tải về quá lớn."
        case .fileRead(let message):
            return "Không đọc được tệp: \(message)"
        case .fileWrite(let message):
            return "Không ghi được tệp nguồn: \(message)"
        case .notFound(let packageId):
            return "Không tìm thấy nguồn \(packageId)."
        case .unsafePath:
            return "Từ chối thao tác file ngoài thư mục tiện ích."
        case .index(let message):
            return "Lỗi lưu danh sách tiện ích: \(message)"
        }
    }
}
