import Foundation

/// Sao lưu / phục hồi **cài đặt & cấu hình** của app — tức phần `UserDefaults` do app tự ghi
/// (`@AppStorage` và mọi `UserDefaults.standard.set`).
///
/// Cố ý **không** gắn với một `BackupScope` mới: `BackupManifest.scopes` là `[BackupScope]` decode
/// nghiêm ngặt, thêm case mới sẽ làm bản app cũ đọc `manifest.json` lỗi hoàn toàn. Vì vậy khối cài
/// đặt luôn được ghi vào archive (chỉ vài KB) và phía khôi phục bật/tắt bằng
/// `BackupRestoreWorker.Options.restoreSettings`.
///
/// Dùng plist nhị phân thay vì JSON vì `UserDefaults` chứa cả `Bool`/`Int`/`Double`/`Date`/`Data`/
/// mảng/từ điển — plist giữ đúng kiểu, JSON thì làm `Bool` thành số và mất `Date`/`Data`.
public enum BackupSettingsArchiver {
    public struct Report: Sendable {
        public var restoredKeys: Int = 0
        public var errors: [String] = []

        public init() {}
    }

    // MARK: - Lọc khoá

    /// Khoá không bao giờ được sao lưu, kèm lý do:
    /// - hai khoá đầu là **bí mật/định danh OAuth** của riêng máy đó;
    /// - `ttsExtensionLocalPath` là đường dẫn **tuyệt đối** chứa UUID container của máy cũ (cùng lý do
    ///   `BackupLibraryReader` phải tương đối hoá `Extension.localPath`) — phục hồi nó là trỏ vào
    ///   đường dẫn không tồn tại;
    /// - ba mốc `...LastRunAt` / `LastBatchAt` quyết định lần chạy nền kế tiếp: mang mốc của máy cũ
    ///   sang sẽ làm lượt tự động chạy sai thời điểm;
    /// - hai hàng đợi `failed_*` là việc dở của riêng máy đó.
    private static let deniedKeys: Set<String> = [
        "google_cloud_tts_custom_api_key",
        "googleDriveClientId",
        "ttsExtensionLocalPath",
        "driveAutoBackupLastRunAt",
        "staleBookCleanupLastRunAt",
        "newChapterLastBatchAt",
        "failed_file_deletions_queue",
        "failed_chapterstore_deletions_queue"
    ]

    /// Tiền tố bị loại:
    /// - `lastChapterIndex_` / `lastParagraphIndex_`: tiến độ đọc, do nhóm `.books` (bảng SwiftData)
    ///   sở hữu — phục hồi từ đây sẽ đá nhau với bản trong thư viện;
    /// - `failed_file_deletions_retry_count_`: đếm lần thử xoá file của riêng máy đó;
    /// - `ttsSleepTimer`: trạng thái hẹn giờ của phiên phát, không phải cấu hình.
    private static let deniedKeyPrefixes = [
        "lastChapterIndex_",
        "lastParagraphIndex_",
        "failed_file_deletions_retry_count_",
        "ttsSleepTimer"
    ]

    /// Tiền tố của khoá do hệ thống ghi vào cùng domain (`com.apple.*`, `kCF*`). Các khoá hệ thống
    /// còn lại đều bắt đầu bằng chữ in hoa (`Apple*`, `NS*`, `WebKit*`, `PK*`…) nên bị chặn bởi luật
    /// "chữ đầu phải là chữ thường" ở `isExportable`.
    private static let systemKeyPrefixes = ["com.apple.", "kCF"]

    /// Khoá của app luôn là camelCase hoặc snake_case bắt đầu bằng chữ thường; đây là ranh giới rẻ
    /// nhất để không mang theo rác của hệ thống. Thêm khoá cài đặt mới thì tự động được sao lưu.
    static func isExportable(key: String) -> Bool {
        guard let first = key.first, first.isASCII, first.isLowercase else { return false }
        if deniedKeys.contains(key) { return false }
        if systemKeyPrefixes.contains(where: { key.hasPrefix($0) }) { return false }
        if deniedKeyPrefixes.contains(where: { key.hasPrefix($0) }) { return false }
        return true
    }

    /// Ảnh chụp phần `UserDefaults` được phép mang đi. Giá trị nào không hợp lệ với plist thì bỏ
    /// qua thay vì để `PropertyListSerialization` bắn exception ObjC (không catch được bằng `try`).
    static func exportableSnapshot() -> [String: Any] {
        var snapshot: [String: Any] = [:]
        for (key, value) in UserDefaults.standard.dictionaryRepresentation() where isExportable(key: key) {
            guard PropertyListSerialization.propertyList(["value": value], isValidFor: .binary) else { continue }
            snapshot[key] = value
        }
        return snapshot
    }

    // MARK: - Hai chiều

    /// Ghi khối cài đặt vào staging. Trả về số khoá đã ghi (0 nếu không có gì để ghi).
    public static func stage(into staging: URL) throws -> Int {
        let snapshot = exportableSnapshot()
        guard !snapshot.isEmpty else { return 0 }

        let data = try PropertyListSerialization.data(
            fromPropertyList: snapshot,
            format: .binary,
            options: 0
        )
        try BackupZipArchive.stage(data: data, entryName: BackupPaths.settings, in: staging)
        AppLogger.shared.log("💾 [Backup] Đã sao lưu \(snapshot.count) khoá cài đặt")
        return snapshot.count
    }

    /// Ghi các khoá trong archive vào `UserDefaults` hiện tại (ghi đè khoá cùng tên, không xoá khoá
    /// mà archive không có). Archive cũ không chứa entry này thì trả về báo cáo rỗng.
    public static func restore(from directory: URL) -> Report {
        var report = Report()
        guard let data = BackupZipArchive.readStaged(entryName: BackupPaths.settings, in: directory) else {
            return report
        }

        let object = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        guard let stored = object as? [String: Any] else {
            report.errors.append("Không đọc được khối cài đặt trong bản sao lưu")
            return report
        }

        let defaults = UserDefaults.standard
        // Lọc lại lần nữa ở chiều đọc: file có thể do bản app khác tạo, không tin danh sách của nó.
        for (key, value) in stored where isExportable(key: key) {
            defaults.set(value, forKey: key)
            report.restoredKeys += 1
        }

        if report.restoredKeys > 0 {
            AppLogger.shared.log("♻️ [Restore] Đã phục hồi \(report.restoredKeys) khoá cài đặt")
        }
        return report
    }
}
