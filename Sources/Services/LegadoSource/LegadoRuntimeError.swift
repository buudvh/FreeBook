import Foundation

/// Lỗi của phân hệ nguồn Legado.
///
/// Nguyên tắc: **không im lặng trả rỗng**. Rule thiếu, cú pháp ngoài phạm vi, hay trang không có nội
/// dung đều thành lỗi có tên để màn hình quản lý nguồn và console gỡ lỗi nói được lý do.
public enum LegadoRuntimeError: LocalizedError {
    case missingRule(String)
    case unsupported(LegadoUnsupportedFeature, String)
    case emptyResult(String)
    case sourceNotFound(String)
    case invalidSourceJSON(String)

    public var errorDescription: String? {
        switch self {
        case .missingRule(let name):
            return "Nguồn thiếu rule bắt buộc: \(name)"
        case .unsupported(let feature, let detail):
            return "\(feature.explanation) (\(detail))"
        case .emptyResult(let stage):
            return "Không bóc tách được dữ liệu ở bước \(stage)"
        case .sourceNotFound(let packageId):
            return "Không tìm thấy nguồn Legado: \(packageId)"
        case .invalidSourceJSON(let reason):
            return "JSON nguồn không hợp lệ: \(reason)"
        }
    }
}
