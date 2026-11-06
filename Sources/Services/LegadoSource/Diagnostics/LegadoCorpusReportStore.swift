import Foundation

/// Lối ghi báo cáo nghiệm thu Legado của `LegadoCorpusRunner` vào `applicationSupport/legado_reports/`.
///
/// Từ 1.3.759 chỉ là lớp mỏng: file do `CheckReportStore` (chủ duy nhất của thư mục, cùng thư mục báo cáo tiện ích JS)
/// ghi, liệt kê, xoá và tự dọn (giữ 20 bản mới nhất). Tên file = thời điểm bắt đầu lượt chạy (`yyyyMMdd-HHmmss.json`),
/// nên các lần ghi giữa chừng của cùng một lượt ghi đè cùng một file.
enum LegadoCorpusReportStore {
    static var directoryName: String { CheckReportKind.legado.directoryName }

    /// Ghi báo cáo, trả đường dẫn **tương đối** so với `applicationSupport` (vd `legado_reports/20261021-153000.json`).
    @discardableResult
    static func write(_ report: LegadoCorpusReport, startedAt: Date) throws -> String {
        try CheckReportStore.write(report, kind: .legado, startedAt: startedAt)
    }

    static func fileName(for date: Date) -> String {
        CheckReportStore.fileName(for: date)
    }
}
