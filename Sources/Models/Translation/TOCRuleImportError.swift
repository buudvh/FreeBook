import Foundation

public enum TOCRuleImportError: LocalizedError, Equatable {
    case fileNotFound
    case jsonParseError(String)
    case invalidStructure
    case fileTooLarge(maxKB: Int)
    case invalidJSON
    case tooManyRules(count: Int, max: Int)
    case emptyID(index: Int)
    case idTooLong(index: Int)
    case emptyName(index: Int, id: String)
    case nameTooLong(index: Int)
    case duplicateID(id: String)
    case invalidRegex(ruleName: String, reason: String)

    public var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "Không tìm thấy file quy tắc TOC."
        case .jsonParseError(let msg):
            return "Lỗi cấu trúc JSON: \(msg)"
        case .invalidStructure:
            return "Cấu trúc dữ liệu quy tắc TOC không hợp lệ."
        case .fileTooLarge(let maxKB):
            return "File vượt quá giới hạn dung lượng \(maxKB) KB."
        case .invalidJSON:
            return "File JSON không hợp lệ."
        case .tooManyRules(let count, let max):
            return "Số lượng quy tắc (\(count)) vượt quá giới hạn tối đa (\(max))."
        case .emptyID(let index):
            return "Quy tắc tại dòng \(index + 1) thiếu ID."
        case .idTooLong(let index):
            return "ID quy tắc tại dòng \(index + 1) quá dài."
        case .emptyName(let index, _):
            return "Quy tắc tại dòng \(index + 1) thiếu tên."
        case .nameTooLong(let index):
            return "Tên quy tắc tại dòng \(index + 1) quá dài."
        case .duplicateID(let id):
            return "Trùng lặp ID quy tắc: \(id)."
        case .invalidRegex(let ruleName, let reason):
            return "Biểu thức chính quy không hợp lệ cho '\(ruleName)': \(reason)."
        }
    }
}
