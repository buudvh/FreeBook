import Foundation

public enum TOCRuleImportError: LocalizedError {
    case fileNotFound
    case jsonParseError(String)
    case invalidStructure

    public var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "Không tìm thấy file quy tắc TOC."
        case .jsonParseError(let msg):
            return "Lỗi cấu trúc JSON: \(msg)"
        case .invalidStructure:
            return "Cấu trúc dữ liệu quy tắc TOC không hợp lệ."
        }
    }
}
