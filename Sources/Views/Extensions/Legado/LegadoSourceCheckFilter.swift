import Foundation

/// Bộ lọc danh sách của màn Kiểm tra nguồn: Tất cả / Lỗi / Đạt, hoặc nguồn lỗi theo một kết luận "lỗi do ai".
enum LegadoSourceCheckFilter: Hashable, Identifiable {
    case all
    case failed
    case passed
    case verdict(LegadoFailureVerdict)

    /// Ba chip cố định (chip kết luận chỉ hiện khi có nguồn).
    static let basic: [LegadoSourceCheckFilter] = [.all, .failed, .passed]

    var id: String {
        switch self {
        case .all: return "all"
        case .failed: return "failed"
        case .passed: return "passed"
        case .verdict(let verdict): return "verdict." + verdict.rawValue
        }
    }

    var label: String {
        switch self {
        case .all: return "Tất cả"
        case .failed: return "Lỗi"
        case .passed: return "Đạt"
        case .verdict(let verdict): return verdict.label
        }
    }

    func matches(_ result: LegadoCorpusReport.SourceResult) -> Bool {
        switch self {
        case .all: return true
        case .failed: return result.outcome == .failed
        case .passed: return result.outcome == .passed
        case .verdict(let verdict): return result.outcome == .failed && result.verdict == verdict
        }
    }
}
