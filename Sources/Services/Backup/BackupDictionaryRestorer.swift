import Foundation

/// Gộp từ điển từ archive vào từ điển đang có trên máy.
///
/// Custom và từ điển riêng từng truyện dùng lại đúng primitive của app (`parseRecords` →
/// `mergedRecords(isMerge: true)` → `persist`), nên **mục đã xoá đi kèm miễn phí**: tombstone
/// là bản ghi có value rỗng nằm ngay trong file TXT.
public enum BackupDictionaryRestorer {
    public struct Report: Sendable {
        public var customFiles = 0
        public var bookFiles = 0
        public var sharedFiles = 0
        public var skippedSharedFiles = 0
        public var errors: [String] = []
    }

    /// - Parameters:
    ///   - bookIdBySlug: bảng tra ngược từ `library/slugs.json`.
    ///   - overwriteShared: người dùng tick "ghi đè từ điển chung"; mặc định chỉ cài khi máy thiếu.
    public static func restore(
        from extractedDirectory: URL,
        scopes: Set<BackupScope>,
        bookIdBySlug: [String: String],
        overwriteShared: Bool
    ) -> Report {
        var report = Report()
        let translateRoot = TranslationManager.shared.translateDirectory

        if scopes.contains(.dictCustom) {
            for name in BackupPaths.globalDictionaryFiles {
                let entry = "\(BackupPaths.globalDictionaryFolder)/\(name)"
                guard let source = BackupZipArchive.stagedURL(entryName: entry, in: extractedDirectory) else { continue }
                let target = translateRoot.appendingPathComponent(name)
                if merge(source: source, target: target, label: name, into: &report) {
                    report.customFiles += 1
                }
            }
            restoreTTSDictionaries(from: extractedDirectory, into: &report)
        }

        if scopes.contains(.dictBooks) {
            let booksRoot = translateRoot.appendingPathComponent("books", isDirectory: true)
            for (slug, bookId) in bookIdBySlug.sorted(by: { $0.key < $1.key }) {
                for name in BackupPaths.bookDictionaryFiles {
                    let entry = "\(BackupPaths.bookDictionaryFolder(slug: slug))/\(name)"
                    guard let source = BackupZipArchive.stagedURL(entryName: entry, in: extractedDirectory) else { continue }
                    let target = booksRoot.appendingPathComponent(bookId, isDirectory: true)
                        .appendingPathComponent(name)
                    if merge(source: source, target: target, label: "\(bookId)/\(name)", into: &report) {
                        report.bookFiles += 1
                    }
                }
            }
        }

        if scopes.contains(.dictShared) {
            restoreShared(
                from: extractedDirectory,
                translateRoot: translateRoot,
                overwrite: overwriteShared,
                into: &report
            )
        }

        return report
    }

    /// Gộp một file TXT dạng `key=value`. Trả `false` khi có lỗi để người gọi không đếm sai.
    private static func merge(source: URL, target: URL, label: String, into report: inout Report) -> Bool {
        do {
            let imported = try DictionaryTextFileStore.parseRecords(from: source)
            let existing = FileManager.default.fileExists(atPath: target.path)
                ? ((try? DictionaryTextFileStore.parseRecords(from: target)) ?? [])
                : []
            let merged = DictionaryTextFileStore.mergedRecords(
                imported: imported,
                existing: existing,
                isMerge: true
            )
            try DictionaryTextFileStore.persist(records: merged, to: target)
            return true
        } catch {
            report.errors.append("Từ điển \(label): \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Bộ tiền xử lý TTS (`FreeBook/TTS/`)

    /// Phục hồi từ điển phiên âm cá nhân của NghiTTS (`non-vietnamese-words.plist`), bảng viết tắt
    /// (`acronyms.plist`) và luật thay ký tự (`character_replacements.json`).
    ///
    /// Không dùng được `DictionaryTextFileStore.merge`: primitive đó chỉ hiểu TXT `key=value`, còn
    /// đây là plist XML và JSON. **Chọn gộp theo key thay vì ghi đè nguyên file**, vì đây là dữ liệu
    /// người dùng tự nhập dần trên nhiều máy — ghi đè sẽ xoá trắng phần chỉ có ở máy đang phục hồi,
    /// trái với nguyên tắc "khôi phục chỉ thêm, không xoá" của phân hệ này. Đổi lại, plist **không
    /// có tombstone** như TXT nên một từ đã xoá có thể sống lại nếu bản sao lưu cũ hơn — chấp nhận
    /// được vì xoá lại một từ rẻ hơn nhập lại cả từ điển.
    ///
    /// Số file phục hồi được cộng vào `Report.customFiles` (không thêm field mới để giữ nguyên
    /// `Report` cho các call site ngoài file này).
    private static func restoreTTSDictionaries(from extractedDirectory: URL, into report: inout Report) {
        let root = BackupPaths.ttsDictionaryDirectory
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        var restoredPlists = 0
        var restoredRules = false

        for name in BackupPaths.ttsDictionaryFiles {
            let entry = "\(BackupPaths.ttsDictionaryFolder)/\(name)"
            guard let source = BackupZipArchive.stagedURL(entryName: entry, in: extractedDirectory) else { continue }
            let target = root.appendingPathComponent(name)

            if name.hasSuffix(".plist") {
                guard mergeStringPlist(source: source, target: target, label: name, into: &report) else { continue }
                report.customFiles += 1
                restoredPlists += 1
            } else {
                guard mergeReplacementRules(source: source, target: target, label: name, into: &report) else { continue }
                report.customFiles += 1
                restoredRules = true
            }
        }

        guard restoredPlists > 0 || restoredRules else { return }
        AppLogger.shared.log(
            "♻️ [Restore] Từ điển phiên âm NghiTTS: \(restoredPlists) plist"
            + (restoredRules ? " + luật thay ký tự" : "")
        )

        // Bộ nhớ trong của `TextPreprocessor` (actor) và `TTSReplacementManager` vẫn giữ bản cũ đọc
        // lúc khởi động — phải nạp lại, nếu không lượt đọc TTS kế tiếp vẫn dùng từ điển cũ.
        if restoredPlists > 0 {
            Task { await TextPreprocessor.shared.loadResources() }
        }
        if restoredRules {
            Task { @MainActor in TTSReplacementManager.shared.loadRules() }
        }
    }

    /// Gộp một plist `[String: String]`: entry của archive ghi đè key trùng, key chỉ có trên máy
    /// được giữ nguyên. Trả `false` khi không đọc/ghi được để người gọi không đếm sai.
    private static func mergeStringPlist(source: URL, target: URL, label: String, into report: inout Report) -> Bool {
        guard let imported = readStringPlist(at: source) else {
            report.errors.append("Từ điển TTS \(label): nội dung không phải plist chuỗi–chuỗi")
            return false
        }

        var merged = readStringPlist(at: target) ?? [:]
        for (key, value) in imported { merged[key] = value }

        do {
            let data = try PropertyListSerialization.data(fromPropertyList: merged, format: .xml, options: 0)
            try data.write(to: target, options: .atomic)
            return true
        } catch {
            report.errors.append("Từ điển TTS \(label): \(error.localizedDescription)")
            return false
        }
    }

    private static func readStringPlist(at url: URL) -> [String: String]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        return plist as? [String: String]
    }

    /// Gộp `character_replacements.json`. Luật là **mảng có thứ tự áp dụng**, nên giữ nguyên thứ tự
    /// bản trên máy rồi nối các luật chỉ có trong archive vào cuối — đúng ngữ nghĩa
    /// `TTSReplacementManager.importRules(mode: .merge)` (trùng `pattern` thì giữ bản của máy).
    /// Không đọc được cấu trúc (file lỗi hoặc schema khác) thì ghi đè nguyên file của archive.
    private static func mergeReplacementRules(source: URL, target: URL, label: String, into report: inout Report) -> Bool {
        do {
            let importedData = try Data(contentsOf: source)
            let decoder = JSONDecoder()

            guard let imported = try? decoder.decode([TTSReplacementRule].self, from: importedData) else {
                try importedData.write(to: target, options: .atomic)
                return true
            }

            guard let existingData = try? Data(contentsOf: target),
                  let existing = try? decoder.decode([TTSReplacementRule].self, from: existingData)
            else {
                try importedData.write(to: target, options: .atomic)
                return true
            }

            var merged = existing
            let existingPatterns = Set(existing.map { $0.pattern })
            merged.append(contentsOf: imported.filter { !existingPatterns.contains($0.pattern) })

            let data = try JSONEncoder().encode(merged)
            try data.write(to: target, options: .atomic)
            return true
        } catch {
            report.errors.append("Luật thay ký tự TTS \(label): \(error.localizedDescription)")
            return false
        }
    }

    private static func restoreShared(
        from extractedDirectory: URL,
        translateRoot: URL,
        overwrite: Bool,
        into report: inout Report
    ) {
        let folder = extractedDirectory.appendingPathComponent(BackupPaths.sharedDictionaryFolder, isDirectory: true)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return }

        for name in names.sorted() {
            let source = folder.appendingPathComponent(name)
            let target = translateRoot.appendingPathComponent(name)

            // Không ghi đè: bỏ qua nếu máy đã có bản `.dat` hoặc `.txt` cùng gốc tên, vì hai bản
            // là cùng dữ liệu và loader ưu tiên `.dat` — cài thêm sẽ che mất bản của người dùng.
            if !overwrite, hasLocalVariant(of: name, in: translateRoot) {
                report.skippedSharedFiles += 1
                continue
            }

            do {
                if FileManager.default.fileExists(atPath: target.path) {
                    try FileManager.default.removeItem(at: target)
                }
                try FileManager.default.copyItem(at: source, to: target)
                report.sharedFiles += 1
            } catch {
                report.errors.append("Từ điển chung \(name): \(error.localizedDescription)")
            }
        }
    }

    private static func hasLocalVariant(of name: String, in translateRoot: URL) -> Bool {
        let base = (name as NSString).deletingPathExtension
        for candidate in ["\(base).dat", "\(base).txt"]
        where FileManager.default.fileExists(atPath: translateRoot.appendingPathComponent(candidate).path) {
            return true
        }
        return false
    }
}
