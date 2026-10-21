import Foundation

/// Lỗi của lớp luồng nguồn Legado (`LegadoSourceRuntime`, nhánh Legado của `SourceRuntime`) — các lỗi **không** do
/// engine ném. Lỗi engine (`LegadoEngineError`) và `CancellationError` đi xuyên qua nguyên vẹn.
enum LegadoRuntimeError: LocalizedError {
    /// Nguồn loại tranh/video/khác — đợt 1 chỉ chạy truyện chữ.
    case unsupportedKind(String)
    /// Không đọc được `source.json` của nguồn đã cài.
    case sourceUnavailable(String)
    /// Nguồn thiếu rule cần cho thao tác (`searchUrl`, `exploreUrl`…).
    case missingRule(String)
    /// `executeCustomScript` với tên script mà nguồn Legado không có (vd bấm thẻ thể loại của trang chi tiết).
    case unsupportedScript(String)

    var category: LegadoEngineError.Category {
        switch self {
        case .unsupportedKind: return .unsupportedSyntax
        case .sourceUnavailable, .missingRule: return .invalidSource
        case .unsupportedScript: return .unsupportedSyntax
        }
    }

    var errorDescription: String? {
        switch self {
        case .unsupportedKind(let label):
            return "Nguồn Legado loại \(label) chưa hỗ trợ ở bản này"
        case .sourceUnavailable(let detail):
            return "Không đọc được nguồn Legado: \(detail)"
        case .missingRule(let rule):
            return "Nguồn Legado không có rule \(rule)"
        case .unsupportedScript(let name):
            let label = name.isEmpty ? "mục này" : "\"\(name)\""
            return "Nguồn Legado không có danh sách cho \(label)"
        }
    }

    /// Phân loại một lỗi bất kỳ của luồng Legado cho bộ chạy nghiệm thu: `cancelled`, các `rawValue` của
    /// `LegadoEngineError.Category` (`unsupportedSyntax`, `http`, `timeout`, `network`, `javaScript`, `noMatch`,
    /// `invalidSource`), hoặc `other`.
    static func categoryName(of error: Error) -> String {
        if error is CancellationError { return "cancelled" }
        if let engine = error as? LegadoEngineError { return engine.category.rawValue }
        if let runtime = error as? LegadoRuntimeError { return runtime.category.rawValue }
        if error is LegadoSourceError { return LegadoEngineError.Category.invalidSource.rawValue }
        return "other"
    }
}
