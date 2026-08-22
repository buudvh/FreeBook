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
