import Foundation

/// Hai loại báo cáo kiểm tra lưu trên máy (trang "Báo cáo kiểm tra", 1.3.759): mỗi loại một thư mục dưới
/// `applicationSupport`, mỗi lượt kiểm tra một file `<yyyyMMdd-HHmmss>.json` (thời điểm bắt đầu lượt).
///
/// `legado_reports` giữ tên cũ (có từ trước khi có trang này) để không phải chuyển dữ liệu; báo cáo tiện ích JS mới được
/// lưu từ 1.3.759 ở `extension_check_reports`. Chủ file duy nhất của cả hai thư mục là `CheckReportStore`.
enum CheckReportKind: String, CaseIterable, Sendable, Identifiable, Hashable {
    case legado
    case script

    var id: String { rawValue }

    var title: String {
        switch self {
        case .legado: return "Nguồn Legado"
        case .script: return "Tiện ích JS"
        }
    }

    /// Đơn vị đếm của một lượt: nguồn (Legado) hoặc tiện ích (JS).
    var unitName: String {
        switch self {
        case .legado: return "nguồn"
        case .script: return "tiện ích"
        }
    }

    var directoryName: String {
        switch self {
        case .legado: return "legado_reports"
        case .script: return "extension_check_reports"
        }
    }

    var directoryURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent(directoryName, isDirectory: true)
    }
}
