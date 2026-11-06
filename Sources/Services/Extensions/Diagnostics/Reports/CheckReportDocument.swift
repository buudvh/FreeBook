import Foundation

/// Nội dung đầy đủ của một báo cáo kiểm tra đã lưu (màn chi tiết chỉ xem của trang Báo cáo kiểm tra).
enum CheckReportDocument: Sendable {
    case legado(LegadoCorpusReport)
    case script(ExtensionCheckReport)

    /// Ghi tệp chia sẻ qua hai bộ ghi sẵn có (thư mục tạm riêng, tên `kiem-tra-…-<thời điểm>.json`, đã redact như
    /// lúc chia sẻ từ màn kiểm tra).
    func writeShareFile() async -> Result<URL, Error> {
        switch self {
        case .legado(let report):
            return await LegadoCorpusReportShare.write(report).mapError { $0 as Error }
        case .script(let report):
            return await ExtensionCheckReportShare.write(report).mapError { $0 as Error }
        }
    }
}
