import Foundation

/// Bộ lọc danh sách của màn Kiểm tra tiện ích hàng loạt: Tất cả / Có lỗi / Đạt đủ. Tiện ích đang chạy chỉ hiện ở
/// "Tất cả".
enum ExtensionCheckFilter: String, CaseIterable, Identifiable {
    case all
    case problems
    case passed

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "Tất cả"
        case .problems: return "Có lỗi"
        case .passed: return "Đạt đủ"
        }
    }

    func matches(_ result: ExtensionCheckReport.ExtensionResult) -> Bool {
        switch self {
        case .all: return true
        case .problems: return result.state == .finished && result.hasProblem
        case .passed: return result.state == .finished && !result.hasProblem
        }
    }
}
