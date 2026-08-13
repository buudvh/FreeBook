import Foundation

public enum ExtensionTransactionError: LocalizedError {
    case saveFailed(String)
    case entityNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .saveFailed(let msg): return "Lưu cơ sở dữ liệu thất bại: \(msg)"
        case .entityNotFound(let name): return "Không tìm thấy dữ liệu: \(name)"
        }
    }
}
