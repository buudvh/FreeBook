import Foundation
import Combine

/// Chủ sở hữu duy nhất của **hai file tắt rule**:
///
/// - chung: `translate/QuickTranslateRulesDisabled.txt`
/// - riêng truyện: `translate/books/<bookId>/QuickTranslateRulesDisabled.txt`
///
/// Ngữ nghĩa **giống VP riêng / VP chung** (xem `snapshot(bookId:)`): tắt ở phạm vi chung là tắt cho
/// **mọi** truyện; muốn dùng lại rule đó ở một truyện thì thêm mẫu vào bộ rule riêng của truyện, vì
/// rule của bộ riêng chỉ chịu file tắt riêng.
///
/// Ranh giới tầng: Service nên **không** `import SwiftUI` và **không** gọi `ToastManager` — trả
/// `Outcome`, View tự phát toast.
public final class QuickTranslationRuleDisableStore: ObservableObject {
    public static let shared = QuickTranslationRuleDisableStore()

    public static let fileName = "QuickTranslateRulesDisabled.txt"

    public enum Outcome: Sendable {
        case success
        case failure(message: String)
    }

    /// Bản chụp bất biến hai tập mẫu đang tắt, đủ để engine quyết định cho **một** lượt rewrite.
    public struct Snapshot: Sendable {
        public let global: Set<String>
        public let book: Set<String>

        public var isEmpty: Bool { global.isEmpty && book.isEmpty }

        public init(global: Set<String>, book: Set<String>) {
            self.global = global
            self.book = book
        }

        /// `scopeRank` lấy từ `QuickTranslationCompiledRule.scopeRank` (0 = bộ riêng, 1 = bộ chung).
        public func isDisabled(pattern: String, scopeRank: Int) -> Bool {
            if book.contains(pattern) { return true }
            return scopeRank != 0 && global.contains(pattern)
        }
    }

    /// Chỉ để `@Published` đẩy UI; **không** đi vào cache key dịch (đường invalidation đã đủ,
    /// xem `notifyChange`).
    @MainActor @Published public private(set) var revision = 0

    private let lock = NSLock()
    private nonisolated(unsafe) var globalPatterns: [String]?
    private nonisolated(unsafe) var bookPatterns: [String: [String]] = [:]

    private init() {}

    // MARK: - Đường dẫn

    public func fileURL(for scope: QuickTranslationRuleScope) -> URL {
        let root = TranslationManager.shared.translateDirectory
        switch scope {
        case .global:
            return root.appendingPathComponent(Self.fileName)
        case .book(let bookId):
            return root
                .appendingPathComponent("books")
                .appendingPathComponent(bookId)
                .appendingPathComponent(Self.fileName)
        }
    }

    // MARK: - Đọc

    /// Danh sách mẫu đang tắt của một phạm vi, giữ thứ tự trong file.
    public func disabledPatterns(for scope: QuickTranslationRuleScope) -> [String] {
        lock.lock()
        if let cached = cachedPatterns(for: scope) {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let loaded = readFile(for: scope)
        lock.lock()
        store(loaded, for: scope)
        lock.unlock()
        return loaded
    }

    /// Bản chụp cho một lượt rewrite. `bookId == nil` ⇒ tập riêng rỗng (đường dịch meta/global).
    public func snapshot(bookId: String?) -> Snapshot {
        let global = Set(disabledPatterns(for: .global))
        guard let bookId, !bookId.isEmpty else {
            return Snapshot(global: global, book: [])
        }
        return Snapshot(global: global, book: Set(disabledPatterns(for: .book(bookId))))
    }

    public func isDisabled(pattern: String, in scope: QuickTranslationRuleScope) -> Bool {
        disabledPatterns(for: scope).contains(pattern)
    }

    // MARK: - Ghi

    /// Tắt/bật một mẫu ở một phạm vi.
    ///
    /// Ghi file thất bại ⇒ **không** đổi cache, **không** bump revision, **không** phát thông báo —
    /// trả lỗi để View báo và trả `Toggle` về trạng thái cũ.
    @discardableResult
    public func setDisabled(
        _ disabled: Bool,
        pattern rawPattern: String,
        scope: QuickTranslationRuleScope
    ) -> Outcome {
        let pattern = rawPattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pattern.isEmpty else {
            return .failure(message: "Mẫu rule không được để trống")
        }

        let current = disabledPatterns(for: scope)
        let updated = disabled
            ? QuickTranslationRuleDisableFile.adding(pattern, to: current)
            : QuickTranslationRuleDisableFile.removing(pattern, from: current)

        // Không có gì đổi thì đây là no-op thật sự: không ghi đĩa, không phát thông báo.
        guard updated != current else { return .success }

        if let message = write(updated, for: scope) {
            return .failure(message: message)
        }

        lock.lock()
        store(updated, for: scope)
        lock.unlock()

        AppLogger.shared.log(
            "🔕 [QuickTranslateRule] \(disabled ? "Tắt" : "Bật") mẫu \(pattern) ở phạm vi"
            + " \(scope.label) — còn \(updated.count) mẫu đang tắt"
        )
        notifyChange(scope: scope)
        return .success
    }

    /// Dùng cho chiều khôi phục backup: hợp tập rồi ghi một lần.
    @discardableResult
    public func merge(patterns imported: [String], into scope: QuickTranslationRuleScope) -> Outcome {
        guard !imported.isEmpty else { return .success }
        let current = disabledPatterns(for: scope)
        let merged = QuickTranslationRuleDisableFile.union(current: current, imported: imported)
        guard merged != current else { return .success }

        if let message = write(merged, for: scope) {
            return .failure(message: message)
        }
        lock.lock()
        store(merged, for: scope)
        lock.unlock()
        return .success
    }

    /// Nhập danh sách mẫu tắt cho một phạm vi.
    /// - `.replaceAll`: danh sách mới hoàn toàn thay thế danh sách cũ.
    /// - `.overwriteExisting` / `.keepExisting`: gộp (union) danh sách cũ và mới — tập mẫu không có "giá trị" nên hai mode này đồng nghĩa.
    /// Luôn `notifyChange` để Reader/TTS cập nhật (khác `merge` vốn im lặng dùng cho backup).
    @discardableResult
    public func importPatterns(
        imported: [String],
        mode: DataImportMode,
        scope: QuickTranslationRuleScope
    ) -> Outcome {
        let current = disabledPatterns(for: scope)
        let updated: [String]
        switch mode {
        case .replaceAll:
            updated = imported
        case .overwriteExisting, .keepExisting:
            updated = QuickTranslationRuleDisableFile.union(current: current, imported: imported)
        }
        guard updated != current else { return .success }

        if let message = write(updated, for: scope) {
            return .failure(message: message)
        }
        lock.lock()
        store(updated, for: scope)
        lock.unlock()
        notifyChange(scope: scope)
        return .success
    }

    /// Xoá toàn bộ file tắt rule của một phạm vi (bật lại mọi rule đang tắt).
    /// Kết quả rỗng thì `write` tự xoá file trên đĩa.
    @discardableResult
    public func clearDisabled(scope: QuickTranslationRuleScope) -> Outcome {
        let current = disabledPatterns(for: scope)
        guard !current.isEmpty else { return .success }

        if let message = write([], for: scope) {
            return .failure(message: message)
        }
        lock.lock()
        store([], for: scope)
        lock.unlock()
        notifyChange(scope: scope)
        return .success
    }

    /// Bỏ cache của một truyện — gọi khi đổi nguồn (bookId đổi) hoặc sau khi khôi phục backup.
    public func invalidateCache(for scope: QuickTranslationRuleScope? = nil) {
        lock.lock()
        switch scope {
        case .none:
            globalPatterns = nil
            bookPatterns.removeAll()
        case .some(.global):
            globalPatterns = nil
        case .some(.book(let bookId)):
            bookPatterns.removeValue(forKey: bookId)
        }
        lock.unlock()
        bumpRevision()
    }

    // MARK: - Phụ trợ

    private func cachedPatterns(for scope: QuickTranslationRuleScope) -> [String]? {
        switch scope {
        case .global: return globalPatterns
        case .book(let bookId): return bookPatterns[bookId]
        }
    }

    private func store(_ patterns: [String], for scope: QuickTranslationRuleScope) {
        switch scope {
        case .global: globalPatterns = patterns
        case .book(let bookId): bookPatterns[bookId] = patterns
        }
    }

    private func readFile(for scope: QuickTranslationRuleScope) -> [String] {
        guard let text = try? String(contentsOf: fileURL(for: scope), encoding: .utf8) else { return [] }
        return QuickTranslationRuleDisableFile.parse(text)
    }

    /// Trả `nil` khi ghi xong; trả message khi lỗi. Hết mẫu thì **xoá file** để không để lại rác.
    private func write(_ patterns: [String], for scope: QuickTranslationRuleScope) -> String? {
        let url = fileURL(for: scope)
        if patterns.isEmpty {
            if FileManager.default.fileExists(atPath: url.path) {
                do {
                    try FileManager.default.removeItem(at: url)
                } catch {
                    return "Không xoá được file tắt rule: \(error.localizedDescription)"
                }
            }
            return nil
        }

        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let text = QuickTranslationRuleDisableFile.serialize(patterns)
            try Data(text.utf8).write(to: url, options: .atomic)
            return nil
        } catch {
            return "Không ghi được file tắt rule: \(error.localizedDescription)"
        }
    }

    /// Đúng **một** lời gọi cho mọi thứ còn lại: `notifyDictionariesDidUpdate` →
    /// `TranslateUtils.invalidateCache(bookId:)` đã tự `QuickTranslationRuleEngine.clearCache()` ở
    /// dòng đầu và bump generation, rồi post `.translationDictionariesDidUpdate` để Reader/TTS dựng
    /// lại. Vì vậy ở đây **không** gọi thêm `clearCache()` và **không** thêm notification mới.
    private func notifyChange(scope: QuickTranslationRuleScope) {
        bumpRevision()
        TranslationManager.shared.notifyDictionariesDidUpdate(
            bookId: scope.bookId,
            scope: .config(bookId: scope.bookId)
        )
    }

    private func bumpRevision() {
        Task { @MainActor in
            self.revision += 1
        }
    }
}
