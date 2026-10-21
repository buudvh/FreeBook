import Foundation

/// Chủ duy nhất của thư mục `applicationSupport/legado_reports/`: ghi báo cáo nghiệm thu dạng JSON.
///
/// Tên file = thời điểm bắt đầu lượt chạy (`yyyyMMdd-HHmmss.json`), nên các lần ghi giữa chừng của cùng một lượt ghi đè
/// cùng một file. Mọi thao tác file qua `validatePathSafety(for:)` (cài lại riêng ở owner này, như các owner khác).
enum LegadoCorpusReportStore {
    static let directoryName = "legado_reports"

    enum StoreError: LocalizedError {
        case unsafePath
        case encodeFailed
        case writeFailed(String)

        var errorDescription: String? {
            switch self {
            case .unsafePath: return "Truy cập file ngoài thư mục legado_reports bị từ chối."
            case .encodeFailed: return "Không mã hoá được báo cáo nghiệm thu."
            case .writeFailed(let message): return "Không ghi được báo cáo nghiệm thu: \(message)"
            }
        }
    }

    private static var rootURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent(directoryName, isDirectory: true)
    }

    /// Ghi báo cáo, trả đường dẫn **tương đối** so với `applicationSupport` (vd `legado_reports/20261021-153000.json`).
    @discardableResult
    static func write(_ report: LegadoCorpusReport, startedAt: Date) throws -> String {
        let name = Self.fileName(for: startedAt)
        let root = rootURL
        let target = root.appendingPathComponent(name, isDirectory: false)
        try validatePathSafety(for: target)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(report) else { throw StoreError.encodeFailed }
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try data.write(to: target, options: [.atomic])
        } catch {
            throw StoreError.writeFailed(error.localizedDescription)
        }
        return directoryName + "/" + name
    }

    static func fileName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date) + ".json"
    }

    private static func validatePathSafety(for targetURL: URL) throws {
        let canonicalRoot = rootURL.standardized.resolvingSymlinksInPath()
        let canonicalTarget = targetURL.standardized.resolvingSymlinksInPath()
        guard canonicalTarget.pathComponents.count > canonicalRoot.pathComponents.count,
              canonicalTarget.pathComponents.starts(with: canonicalRoot.pathComponents) else {
            throw StoreError.unsafePath
        }
    }
}
