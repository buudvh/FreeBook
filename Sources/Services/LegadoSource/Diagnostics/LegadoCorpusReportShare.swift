import Foundation

/// Tệp JSON của **một** lượt Kiểm tra nguồn để chia sẻ (nút chia sẻ ở màn Kiểm tra nguồn) — View không ghi file.
///
/// - Nội dung: chính `LegadoCorpusReport` kèm `sources` — vốn đã redact (không nội dung chương, cookie, header, thân
///   phản hồi; URL trong thông điệp/lý do bỏ giá trị query, khối option `,{…}` bị che).
/// - Ghi vào thư mục tạm riêng `tmp/legado_check_share/` (dọn tệp cũ mỗi lần ghi), trên hàng đợi tệp của kho nguồn
///   (ngoài main). Mọi thao tác file qua `validatePathSafety(for:)` của chính type này.
enum LegadoCorpusReportShare {
    static let directoryName = "legado_check_share"

    enum ShareError: LocalizedError, Sendable {
        case unsafePath
        case encodeFailed
        case writeFailed(String)

        var errorDescription: String? {
            switch self {
            case .unsafePath: return "Truy cập file ngoài thư mục chia sẻ báo cáo bị từ chối."
            case .encodeFailed: return "Không mã hoá được báo cáo kiểm tra."
            case .writeFailed(let message): return "Không ghi được tệp báo cáo: \(message)"
            }
        }
    }

    static var shareRoot: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(directoryName, isDirectory: true)
    }

    /// Ghi tệp (ngoài main) và trả URL để trình bày share sheet.
    static func write(_ report: LegadoCorpusReport) async -> Result<URL, ShareError> {
        await LegadoSourceCoordinator.runOnFileQueue {
            Self.writeNow(report, date: Date())
        }
    }

    static func writeNow(_ report: LegadoCorpusReport, date: Date) -> Result<URL, ShareError> {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(report) else { return .failure(.encodeFailed) }
        let root = shareRoot
        let target = root.appendingPathComponent(fileName(for: date), isDirectory: false)
        do {
            try validatePathSafety(for: target)
            let old = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
            for file in old where (try? validatePathSafety(for: file)) != nil {
                try? FileManager.default.removeItem(at: file)
            }
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try data.write(to: target, options: [.atomic])
        } catch let error as ShareError {
            return .failure(error)
        } catch {
            return .failure(.writeFailed(error.localizedDescription))
        }
        AppLogger.shared.log("📤 [LegadoCorpus] Xuất báo cáo kiểm tra để chia sẻ (\(data.count) byte)")
        return .success(target)
    }

    /// `kiem-tra-nguon-legado-<yyyyMMdd-HHmmss>.json`.
    static func fileName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "kiem-tra-nguon-legado-\(formatter.string(from: date)).json"
    }

    /// Đường dẫn phải nằm **trong** `tmp/legado_check_share/` (sau khi chuẩn hoá `.`/`..`).
    static func validatePathSafety(for targetURL: URL) throws {
        let root = shareRoot.standardizedFileURL
        let target = targetURL.standardizedFileURL
        guard target.pathComponents.count > root.pathComponents.count,
              target.pathComponents.starts(with: root.pathComponents) else {
            throw ShareError.unsafePath
        }
    }
}
