import Foundation

/// Tệp JSON của **một** lượt Kiểm tra tiện ích để chia sẻ (nút chia sẻ của màn kiểm tra) — View không ghi file.
///
/// - Nội dung: chính `ExtensionCheckReport` — vốn đã redact (không nội dung chương, cookie, header, thân phản hồi; URL
///   trong thông điệp bỏ giá trị query); `errorLink` không vào JSON.
/// - Ghi vào thư mục tạm riêng `tmp/extension_check_share/` (dọn tệp cũ mỗi lần ghi), ngoài main. Mọi thao tác file qua
///   `validatePathSafety(for:)` của chính type này.
enum ExtensionCheckReportShare {
    static let directoryName = "extension_check_share"

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
    static func write(_ report: ExtensionCheckReport) async -> Result<URL, ShareError> {
        await Task.detached(priority: .utility) {
            ExtensionCheckReportShare.writeNow(report, date: Date())
        }.value
    }

    static func writeNow(_ report: ExtensionCheckReport, date: Date) -> Result<URL, ShareError> {
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
        AppLogger.shared.log("📤 [ExtCheck] Xuất báo cáo kiểm tra tiện ích để chia sẻ (\(data.count) byte)")
        return .success(target)
    }

    /// `kiem-tra-tien-ich-<yyyyMMdd-HHmmss>.json`.
    static func fileName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "kiem-tra-tien-ich-\(formatter.string(from: date)).json"
    }

    /// Đường dẫn phải nằm **trong** `tmp/extension_check_share/` (sau khi chuẩn hoá `.`/`..`).
    static func validatePathSafety(for targetURL: URL) throws {
        let root = comparableComponents(shareRoot)
        let target = comparableComponents(targetURL)
        guard target.count > root.count, target.starts(with: root) else {
            throw ShareError.unsafePath
        }
    }

    /// Thành phần đường dẫn đã chuẩn hoá, bỏ tiền tố `/private` (thư mục tạm iOS nằm dưới `/private/var/…`, mà
    /// `standardizedFileURL` chỉ bỏ `/private` khi đường dẫn đã tồn tại — xem `LegadoCorpusReportShare`).
    private static func comparableComponents(_ url: URL) -> [String] {
        var parts = url.standardizedFileURL.pathComponents
        if parts.count > 1, parts[0] == "/", parts[1] == "private" {
            parts.remove(at: 1)
        }
        return parts
    }
}
