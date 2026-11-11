import Foundation

/// Thiết lập theo `bookId` phải đi theo truyện khi đổi nguồn (bookId đổi): từ điển + rule riêng, phiên AI chat, trí nhớ
/// AI, phạm vi + điểm tiếp nối quét tên riêng, chế độ dịch riêng, bộ dịch riêng (`TranslationEngineStore`). Thêm kho mới khoá theo `bookId` ⇒ thêm vào **cả hai** hàm.
///
/// Từ 1.3.689 tách hai bước: `copyBookScopedSettings` chỉ **chép** (không đụng bản cũ; truyện đích đã có bản riêng thì giữ
/// của đích), `removeBookScopedSettings` xoá bản của một truyện sau mốc chốt (hoặc của truyện mới khi lùi lại). Trước đây
/// chuyển rồi xoá ngay ⇒ app chết trước khi xoá truyện cũ thì truyện cũ mất hết thiết lập riêng.
/// Chép chương đã tải: `BookSourceChapterCopier`. Điều phối cả lượt: `BookSourceChangeCoordinator`.
public actor BookSourceMigrator {
    public static let shared = BookSourceMigrator()

    private init() {}

    /// Chặn đổi nguồn sang tiện ích **khác loại** (chữ/tranh/video): mục lục, tiến độ (`paragraphIndex` là đoạn /
    /// chỉ số ảnh / số giây) và chương đã tải không chuyển được giữa hai loại. Gọi **trước** mọi lệnh mạng.
    /// `static` (không thuộc actor) nên caller gọi đồng bộ.
    /// Tiện ích cũ đã gỡ và không còn trong catalog ⇒ không biết loại: bỏ qua phép so (không đoán là chữ).
    public static func ensureSameContentKind(oldPackageId: String, newPackageId: String) throws {
        guard let oldKind = ExtensionContentKind.resolveIfKnown(packageId: oldPackageId),
              let newKind = ExtensionContentKind.resolveIfKnown(packageId: newPackageId) else {
            AppLogger.shared.log("⚠️ [BookSourceMigrator] Không tra được loại nội dung (\(oldPackageId) → \(newPackageId)), bỏ qua kiểm tra cùng loại")
            return
        }
        guard oldKind == newKind else {
            let message = "Không thể đổi sang nguồn khác loại (chữ/tranh/video)"
            AppLogger.shared.log("❌ [BookSourceMigrator] \(message): \(oldKind.rawValue) → \(newKind.rawValue)")
            throw ExtensionManagerError.sourceResponse(message: message)
        }
    }

    /// Chép mọi thiết lập riêng của truyện cũ sang truyện đích. Không xoá gì; chạy lại nhiều lần cho cùng kết quả.
    public func copyBookScopedSettings(from oldBookId: String, to newBookId: String) {
        guard oldBookId != newBookId else { return }
        copyTranslationFiles(from: oldBookId, to: newBookId)
        AIChatHistoryStore.shared.copySessions(from: oldBookId, to: newBookId)
        BookAIMemoryStore.shared.copyMemory(from: oldBookId, to: newBookId)
        AINameScanScopeStore.shared.copy(from: oldBookId, to: newBookId)

        let oldOverride = TranslationConfigStore.shared.getBookOverride(bookId: oldBookId)
        if oldOverride != .inherited, TranslationConfigStore.shared.getBookOverride(bookId: newBookId) == .inherited {
            TranslationConfigStore.shared.setBookOverride(bookId: newBookId, mode: oldOverride)
        }
        // Bộ dịch (QT / tiện ích + ngôn ngữ) riêng của truyện.
        if let engine = TranslationEngineStore.shared.bookSelection(bookId: oldBookId),
           TranslationEngineStore.shared.bookSelection(bookId: newBookId) == nil {
            TranslationEngineStore.shared.setBookSelection(engine, bookId: newBookId)
        }
    }

    /// Xoá mọi thiết lập riêng của một truyện (truyện cũ sau mốc chốt, hoặc truyện mới khi lùi lại).
    public func removeBookScopedSettings(bookId: String) {
        // `bookId` rỗng / có "/" hay ".." ⇒ đường dẫn trỏ ra ngoài thư mục của truyện: không bao giờ xoá thư mục.
        let isSafeComponent = !bookId.isEmpty && !bookId.contains("/") && !bookId.contains("..")
        let dir = bookTranslationDirectory(bookId)
        if isSafeComponent, FileManager.default.fileExists(atPath: dir.path) {
            do {
                try FileManager.default.removeItem(at: dir)
            } catch {
                AppLogger.shared.log("❌ [BookSourceMigrator] Không xoá được từ điển/rule riêng của truyện: \(error.localizedDescription)")
            }
        }
        invalidateTranslationCaches(bookId: bookId)
        AIChatHistoryStore.shared.clearAllSessions(for: bookId)
        BookAIMemoryStore.shared.clearMemory(for: bookId)
        AINameScanScopeStore.shared.remove(bookId: bookId)
        if TranslationConfigStore.shared.getBookOverride(bookId: bookId) != .inherited {
            TranslationConfigStore.shared.setBookOverride(bookId: bookId, mode: .inherited)
        }
        if TranslationEngineStore.shared.bookSelection(bookId: bookId) != nil {
            TranslationEngineStore.shared.setBookSelection(nil, bookId: bookId)
        }
    }

    /// File dưới `translate/books/<bookId>/`: chép từng file, file truyện đích đã có thì giữ.
    private func copyTranslationFiles(from oldBookId: String, to newBookId: String) {
        let oldDir = bookTranslationDirectory(oldBookId)
        let newDir = bookTranslationDirectory(newBookId)
        guard FileManager.default.fileExists(atPath: oldDir.path) else { return }

        try? FileManager.default.createDirectory(at: newDir, withIntermediateDirectories: true)
        for name in TranslationManager.bookScopedMigrationFiles {
            let oldFile = oldDir.appendingPathComponent(name)
            let newFile = newDir.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: oldFile.path),
                  !FileManager.default.fileExists(atPath: newFile.path) else { continue }
            do {
                try FileManager.default.copyItem(at: oldFile, to: newFile)
            } catch {
                AppLogger.shared.log("❌ [BookSourceMigrator] Không chép được \(name) sang truyện mới: \(error.localizedDescription)")
            }
        }
        invalidateTranslationCaches(bookId: newBookId)
    }

    private func bookTranslationDirectory(_ bookId: String) -> URL {
        TranslationManager.shared.translateDirectory
            .appendingPathComponent("books")
            .appendingPathComponent(bookId)
    }

    private func invalidateTranslationCaches(bookId: String) {
        QuickTranslationRuleBookStore.shared.invalidate(bookId: bookId)
        QuickTranslationRuleDisableStore.shared.invalidateCache(for: .book(bookId))
    }
}
