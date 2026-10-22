import Foundation

/// Xuất nguồn Legado ra tệp `.json` để chia sẻ (spec §12.1).
///
/// - Nội dung: **mảng JSON** các `source.json` **nguyên văn** đã lưu (giữ khoá lạ, kèm `enabled`/`bookSourceGroup`…
///   người dùng đã sửa trong app), UTF-8 không BOM, khoá sắp xếp, thụt 2 dấu cách; nguồn xếp theo `customOrder` tăng
///   dần rồi theo tên.
/// - **Không** xuất: thông tin/header đăng nhập, cookie, `cache`, biến nguồn — chúng không nằm trong `source.json`.
/// - Tệp ghi vào thư mục tạm riêng `tmp/legado_export/` (dọn tệp cũ mỗi lần xuất); mọi thao tác file qua
///   `validatePathSafety(for:)` của chính type này. Chạy trên `LegadoSourceStore.fileQueue`.
enum LegadoSourceExporter {
    static let directoryName = "legado_export"

    static var exportRoot: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(directoryName, isDirectory: true)
    }

    /// Đọc `source.json` của từng thư mục rồi ghi một tệp mảng. Thư mục đọc lỗi bị bỏ qua (đếm ở `skipped`).
    static func export(directories: [URL], fileName: String) throws -> (url: URL, count: Int, skipped: Int) {
        var entries: [(order: Int, name: String, object: [String: Any])] = []
        var skipped = 0
        for directory in directories {
            guard let data = try? LegadoSourceStore.readSourceData(directory: directory),
                  let object = LegadoModelJSON.parseDocument(data: data) as? [String: Any] else {
                skipped += 1
                continue
            }
            let order = LegadoModelCoercion.int(object["customOrder"]) ?? 0
            let name = LegadoModelCoercion.string(object["bookSourceName"]) ?? ""
            entries.append((order, name, object))
        }
        guard !entries.isEmpty else { throw LegadoSourceError.noSourcesFound }
        entries.sort { lhs, rhs in lhs.order == rhs.order ? lhs.name < rhs.name : lhs.order < rhs.order }
        let array = entries.map { $0.object }
        let data: Data
        do {
            data = try JSONSerialization.data(
                withJSONObject: array,
                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            )
        } catch {
            throw LegadoSourceError.fileWrite(error.localizedDescription)
        }

        let root = exportRoot
        let target = root.appendingPathComponent(fileName)
        try validatePathSafety(for: target)
        do {
            // Dọn tệp xuất cũ (chỉ tệp nằm trong thư mục riêng này).
            let old = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
            for file in old where (try? validatePathSafety(for: file)) != nil {
                try? FileManager.default.removeItem(at: file)
            }
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try data.write(to: target, options: [.atomic])
        } catch {
            throw LegadoSourceError.fileWrite(error.localizedDescription)
        }
        return (target, entries.count, skipped)
    }

    /// Tên tệp: một nguồn ⇒ tên nguồn; nhiều nguồn ⇒ `nguon-legado-<số>-<thời điểm>.json`.
    static func fileName(singleSourceName: String?, count: Int, date: Date = Date()) -> String {
        if count == 1, let name = singleSourceName {
            let cleaned = sanitized(name)
            if !cleaned.isEmpty { return cleaned + ".json" }
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmm"
        return "nguon-legado-\(count)-\(formatter.string(from: date)).json"
    }

    /// Bỏ ký tự cấm trong tên tệp, gộp khoảng trắng, tối đa 60 ký tự.
    private static func sanitized(_ name: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:*?\"<>|").union(.newlines).union(.controlCharacters)
        let parts = name.components(separatedBy: forbidden).joined(separator: " ")
        let collapsed = parts.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        let trimmed = collapsed.trimmingCharacters(in: CharacterSet(charactersIn: ". ").union(.whitespaces))
        return String(trimmed.prefix(60))
    }

    // MARK: - An toàn đường dẫn

    /// Đường dẫn phải nằm **trong** `tmp/legado_export/` (sau khi chuẩn hoá `.`/`..`).
    static func validatePathSafety(for targetURL: URL) throws {
        let root = comparableComponents(exportRoot)
        let target = comparableComponents(targetURL)
        guard target.count > root.count, target.starts(with: root) else {
            throw LegadoSourceError.unsafePath
        }
    }

    /// Thành phần đường dẫn đã chuẩn hoá, **bỏ tiền tố `/private`**. Thư mục tạm của iOS nằm dưới `/private/var/…`, mà
    /// `standardizedFileURL` chỉ bỏ `/private` khi đường dẫn **đã tồn tại**: từ lần xuất thứ hai thư mục đã có (→ `/var/…`)
    /// còn tệp mới thì chưa (→ `/private/var/…`), so sánh lệch và bị từ chối nhầm.
    private static func comparableComponents(_ url: URL) -> [String] {
        var parts = url.standardizedFileURL.pathComponents
        if parts.count > 1, parts[0] == "/", parts[1] == "private" {
            parts.remove(at: 1)
        }
        return parts
    }
}
