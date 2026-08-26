import Foundation

/// Sao lưu / phục hồi các **file cấu hình** không nằm trong `UserDefaults` và cũng không phải từ
/// điển:
/// - `translate/toc_rules.json` — quy tắc regex nhận diện dòng tiêu đề chương khi nhập sách,
/// - `config/search_engines.json` — danh sách công cụ tra cứu nhanh (nguồn thật là `UserDefaults`,
///   nhưng tách ra file riêng để phục hồi **gộp** được thay vì ghi đè cả mảng như khối cài đặt),
/// - `config/QuickTranslateRules.txt` — bộ rule dịch Quick Translate đang có trên máy (tải từ
///   HuggingFace hoặc người dùng nhập; không đi kèm app nên phải sao lưu).
///
/// Không thêm `BackupScope` mới (xem `BackupSettingsArchiver` để biết lý do): luôn ghi vào archive
/// vì chỉ vài KB, phía khôi phục bật/tắt bằng `BackupRestoreWorker.Options.restoreSettings`.
public enum BackupConfigArchiver {
    public struct Report: Sendable {
        /// Số quy tắc mục lục có trong file sao lưu và đã được gộp vào máy.
        public var tocRules = 0
        /// Số công cụ tra cứu **mới** được thêm vào máy.
        public var searchEngines = 0
        /// Số rule dịch đã nạp lại từ file rule trong archive (0 nếu archive không có).
        public var quickTranslateRules = 0
        public var errors: [String] = []

        public var restoredFiles: Int {
            (tocRules > 0 ? 1 : 0) + (searchEngines > 0 ? 1 : 0) + (quickTranslateRules > 0 ? 1 : 0)
        }

        public init() {}
    }

    // MARK: - Xuất

    /// Ghi các file cấu hình vào staging. Trả về số file đã ghi để `manifest.counts.config` báo
    /// đúng cho màn Khôi phục.
    public static func stage(into staging: URL) throws -> Int {
        var staged = 0

        let tocURL = TranslationManager.shared.translateDirectory
            .appendingPathComponent(BackupPaths.tocRulesFileName)
        if FileManager.default.fileExists(atPath: tocURL.path) {
            // Sao lưu nguyên trạng: quy tắc đã tắt (`enabled == false`) cũng phải đi theo, vì đó
            // cũng là lựa chọn của người dùng.
            try BackupZipArchive.stage(fileAt: tocURL, entryName: BackupPaths.tocRules, in: staging)
            staged += 1
        }

        // Đọc thẳng khoá `UserDefaults` thay vì `SearchEngine.loadEngines()`: hàm đó **ghi** bộ mặc
        // định vào máy khi khoá còn trống, không được để chiều xuất gây tác dụng phụ.
        if let data = UserDefaults.standard.data(forKey: SearchEngine.storageKey) {
            try BackupZipArchive.stage(data: data, entryName: BackupPaths.searchEngines, in: staging)
            staged += 1
        }

        let ruleURL = QuickTranslationRuleStore.shared.ruleFileURL
        if FileManager.default.fileExists(atPath: ruleURL.path) {
            try BackupZipArchive.stage(fileAt: ruleURL, entryName: BackupPaths.quickTranslateRules, in: staging)
            staged += 1
        }

        // Rule đã tắt cũng là lựa chọn của người dùng — cùng lý do "quy tắc mục lục đã tắt vẫn phải
        // sao lưu" ở trên.
        let disabledURL = QuickTranslationRuleDisableStore.shared.fileURL(for: .global)
        if FileManager.default.fileExists(atPath: disabledURL.path) {
            try BackupZipArchive.stage(
                fileAt: disabledURL,
                entryName: BackupPaths.quickTranslateRulesDisabled,
                in: staging
            )
            staged += 1
        }

        if staged > 0 {
            AppLogger.shared.log("💾 [Backup] Đã sao lưu \(staged) file cấu hình (quy tắc mục lục / công cụ tra cứu / rule dịch)")
        }
        return staged
    }

    // MARK: - Nhập

    /// Gộp cấu hình trong archive vào máy. Archive cũ không có `config/` thì trả báo cáo rỗng.
    public static func restore(from directory: URL) -> Report {
        var report = Report()
        restoreTOCRules(from: directory, into: &report)
        restoreSearchEngines(from: directory, into: &report)
        restoreQuickTranslateRules(from: directory, into: &report)
        restoreQuickTranslateDisabledRules(from: directory, into: &report)

        if report.restoredFiles > 0 {
            AppLogger.shared.log(
                "♻️ [Restore] Cấu hình: \(report.tocRules) quy tắc mục lục,"
                + " \(report.searchEngines) công cụ tra cứu mới,"
                + " \(report.quickTranslateRules) rule dịch"
            )
        }
        return report
    }

    /// Danh sách rule đang tắt: **hợp tập** mẫu, không ghi đè — đúng nguyên tắc "khôi phục chỉ thêm,
    /// không xoá" của phân hệ này.
    ///
    /// Tradeoff phải biết: khôi phục từ bản sao lưu **cũ hơn** có thể tắt lại một rule người dùng vừa
    /// bật. Chấp nhận được vì bật lại một rule rẻ hơn nhập lại cả danh sách; ngược lại, ghi đè sẽ xoá
    /// trắng những mẫu chỉ có trên máy đang phục hồi.
    private static func restoreQuickTranslateDisabledRules(from directory: URL, into report: inout Report) {
        guard let data = BackupZipArchive.readStaged(
            entryName: BackupPaths.quickTranslateRulesDisabled,
            in: directory
        ), let text = String(data: data, encoding: .utf8) else { return }

        let patterns = QuickTranslationRuleDisableFile.parse(text)
        guard !patterns.isEmpty else { return }

        if case .failure(let message) = QuickTranslationRuleDisableStore.shared.merge(
            patterns: patterns,
            into: .global
        ) {
            report.errors.append("Rule đã tắt: \(message)")
        }
    }

    /// Ghi lại file rule dịch từ archive rồi **nạp lại store ngay**, nhưng **không** để store phát
    /// `notifyDictionariesDidUpdate`: `BackupRestoreWorker` tự phát một lần ở cuối lượt khôi phục
    /// (`:273`). Phát ở đây nữa là Reader dựng lại hai lượt, lượt đầu còn đang dở dữ liệu.
    private static func restoreQuickTranslateRules(from directory: URL, into report: inout Report) {
        guard let data = BackupZipArchive.readStaged(entryName: BackupPaths.quickTranslateRules, in: directory),
              let text = String(data: data, encoding: .utf8) else { return }

        let outcome = QuickTranslationRuleStore.shared.importRules(
            text: text,
            source: .local,
            mode: .replaceAll,
            notifiesObservers: false
        )
        switch outcome {
        case .success(let ruleCount, _):
            report.quickTranslateRules = ruleCount
        case .rejected(let issues):
            report.errors.append("Rule dịch: \(issues.count) dòng lỗi nặng, giữ bộ đang dùng")
        case .failure(let message):
            report.errors.append("Rule dịch: \(message)")
        }
    }

    /// Gộp theo `id` bằng đúng primitive của màn Quy tắc mục lục (`TranslateUtils.mergeTOCRules`):
    /// quy tắc trùng `id` lấy bản trong archive, quy tắc chỉ có trên máy được giữ nguyên.
    /// `saveTOCRules` tự dọn cache regex + cache tiêu đề chương nên không cần gọi thêm.
    private static func restoreTOCRules(from directory: URL, into report: inout Report) {
        guard let data = BackupZipArchive.readStaged(entryName: BackupPaths.tocRules, in: directory) else { return }

        switch TranslateUtils.validateImportedTOCRules(data) {
        case .failure(let error):
            report.errors.append("Quy tắc mục lục: \(error.localizedDescription)")
        case .success(let imported):
            guard !imported.isEmpty else { return }
            let merged = TranslateUtils.mergeTOCRules(current: TranslateUtils.getAllTOCRules(), imported: imported)
            guard TranslateUtils.saveTOCRules(merged) else {
                report.errors.append("Quy tắc mục lục: không ghi được toc_rules.json")
                return
            }
            report.tocRules = imported.count
        }
    }

    /// Chỉ **thêm** công cụ máy chưa có, không sửa và không xoá công cụ đang dùng — cùng nguyên tắc
    /// "khôi phục là gộp" của cả phân hệ.
    private static func restoreSearchEngines(from directory: URL, into report: inout Report) {
        guard let data = BackupZipArchive.readStaged(entryName: BackupPaths.searchEngines, in: directory) else { return }

        switch SearchEngineTransfer.decode(data) {
        case .failure(let error):
            report.errors.append("Công cụ tra cứu nhanh: \(error.localizedDescription)")
        case .success(let imported):
            let current = SearchEngine.loadEngines()
            let merged = SearchEngineTransfer.merged(current: current, imported: imported)
            let added = merged.count - current.count
            guard added > 0 else { return }
            SearchEngine.saveEngines(merged)
            report.searchEngines = added
        }
    }
}
