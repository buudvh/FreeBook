import Foundation

/// **Một** nguồn khai tên các file **riêng truyện** dưới `translate/books/<bookId>/`.
///
/// Trước 1.3.274 danh sách này bị nhân bản ở hai chỗ không biết nhau: `BackupPaths.bookDictionaryFiles`
/// và một mảng hard-code trong luồng đổi nguồn của `SearchView`. Hệ quả: thêm một file riêng truyện mà
/// chỉ sửa một chỗ thì chỗ kia âm thầm bỏ file lại — đúng loại bug không có gì báo.
///
/// Đặt ở extension trong file riêng (không nhồi vào `TranslationManager.swift`) vì file đó đã sát
/// baseline dòng của `check_architecture.py`.
extension TranslationManager {
    /// Từ điển riêng dạng text. Backup chỉ lấy nhóm này (bản `.dat` là cùng dữ liệu nhưng rất lớn).
    public static let bookScopedDictionaryTextFiles = ["VietPhrase.txt", "Names.txt"]

    /// Bản nhị phân của từ điển riêng — chỉ luồng **đổi nguồn** copy theo.
    public static let bookScopedDictionaryBinaryFiles = ["VietPhrase.dat", "Names.dat"]

    /// Bộ rule riêng + danh sách rule đang tắt của truyện.
    public static let bookScopedRuleFiles = [
        QuickTranslationRuleStore.ruleFileName,
        QuickTranslationRuleDisableStore.fileName
    ]

    /// Rule **thay thế ký tự TTS** riêng của truyện (`translate/books/<bookId>/character_replacements.json`).
    ///
    /// Danh sách **riêng**, không gộp vào `bookScopedDictionaryTextFiles`: vòng khôi phục của nhóm đó gộp
    /// bằng `DictionaryTextFileStore.parseRecords` (dạng `key=value`) nên sẽ **phá JSON** — cùng lý do đã
    /// ghi cho `BackupPaths.bookRuleFiles`.
    public static let bookScopedTTSFiles = [TTSReplacementManager.bookRulesFileName]

    /// Mọi file phải đi theo truyện khi **đổi nguồn** (bookId đổi).
    public static var bookScopedMigrationFiles: [String] {
        bookScopedDictionaryBinaryFiles + bookScopedDictionaryTextFiles + bookScopedRuleFiles
            + bookScopedTTSFiles + [QuickTranslationBookEngineConfigStore.fileName]
    }
}
