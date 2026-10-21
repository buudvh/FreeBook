import Foundation

/// Lý do một phần tử bị **bỏ qua** khi nhập nguồn Legado. Thứ tự `allCases` = thứ tự hiện trong alert.
public enum LegadoImportSkipReason: String, Sendable, CaseIterable, Hashable {
    /// `bookSourceType = 1` (spec §1.6).
    case audio
    /// `bookSourceType = 3` — nguồn tải tệp.
    case downloadFile
    /// `bookSourceType` là số khác 0/1/2/3/4.
    case unknownType
    /// Nguồn chữ không đạt "rule tối thiểu" (spec §1.9, bản nới).
    case missingMinimalRules
    case missingSourceUrl
    case missingName
    /// Object kiểu ứng dụng thế hệ trước (có khoá `rule…Url`, không có `bookSourceUrl`) — spec §1.8.
    case legacyFormat
    /// Phần tử mảng không phải object (spec §1.1).
    case notAnObject
    /// Cùng `bookSourceUrl` (sau trim) xuất hiện lần nữa trong cùng lượt nhập — giữ bản gặp trước.
    case duplicateInFile
    /// `packageId` trùng một tiện ích JavaScript đã cài — không ghi đè.
    case conflictsWithExtension
    case writeFailed

    public var label: String {
        switch self {
        case .audio: return "audio"
        case .downloadFile: return "tệp tải về"
        case .unknownType: return "loại lạ"
        case .missingMinimalRules: return "thiếu rule tối thiểu"
        case .missingSourceUrl: return "thiếu bookSourceUrl"
        case .missingName: return "thiếu tên nguồn"
        case .legacyFormat: return "định dạng nguồn cũ"
        case .notAnObject: return "không phải object"
        case .duplicateInFile: return "trùng trong tệp"
        case .conflictsWithExtension: return "trùng mã tiện ích JS"
        case .writeFailed: return "lỗi ghi tệp"
        }
    }
}
