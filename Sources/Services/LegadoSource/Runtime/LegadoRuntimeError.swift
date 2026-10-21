import Foundation

/// Lỗi của lớp luồng nguồn Legado (`LegadoSourceRuntime`, nhánh Legado của `SourceRuntime`) — các lỗi **không** do
/// engine ném. Lỗi engine (`LegadoEngineError`) và `CancellationError` đi xuyên qua nguyên vẹn.
enum LegadoRuntimeError: LocalizedError {
    /// Nguồn loại không lưu được (audio, tệp, giá trị lạ).
    case unsupportedKind(String)
    /// Không đọc được `source.json` của nguồn đã cài.
    case sourceUnavailable(String)
    /// Nguồn thiếu rule cần cho thao tác (`searchUrl`, `exploreUrl`…).
    case missingRule(String)
    /// `executeCustomScript` với tên script mà nguồn Legado không có (vd bấm thẻ thể loại của trang chi tiết).
    case unsupportedScript(String)
    /// Gọi nội dung chữ (`chap`) trên nguồn tranh/video — media không đi pipeline chữ.
    case mediaHasNoText(String)
    /// Chương tranh không có ảnh nào (spec §8.2 bước 6); kèm đoạn chữ đã làm sạch của trang để người dùng tự xem.
    case comicWithoutImages(String)
    /// Tập video không giải ra được nguồn phát (spec §9.3 bước 4.3).
    case noPlayableSource
    /// Dữ liệu server video không phải của nguồn Legado (`VideoServer.data` hỏng).
    case invalidMediaData

    var category: LegadoEngineError.Category {
        switch self {
        case .unsupportedKind: return .unsupportedSyntax
        case .sourceUnavailable, .missingRule: return .invalidSource
        case .unsupportedScript: return .unsupportedSyntax
        case .mediaHasNoText, .invalidMediaData: return .invalidSource
        case .comicWithoutImages, .noPlayableSource: return .noMatch
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
        case .mediaHasNoText(let label):
            return "Nguồn Legado loại \(label) không có nội dung chữ — mở bằng màn đọc tranh/trình phát"
        case .comicWithoutImages(let excerpt):
            return excerpt.isEmpty
                ? "Chương truyện tranh không có ảnh nào"
                : "Chương truyện tranh không có ảnh nào. Nội dung trang:\n\(excerpt)"
        case .noPlayableSource:
            return "Không lấy được nguồn phát của tập này"
        case .invalidMediaData:
            return "Dữ liệu server phát không hợp lệ"
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
