import Foundation
import Combine

/// Chủ sở hữu **bộ rule riêng của từng truyện** (`translate/books/<bookId>/QuickTranslateRules.txt`),
/// song song với `QuickTranslationRuleStore` là chủ bộ chung.
///
/// Vì sao là type riêng chứ không tổng quát hoá store chung: store chung đã sát trần 400 dòng của
/// `check_architecture.py` và mọi method của nó đều hard-code một file duy nhất. Toàn bộ phần khó
/// (parse, compile, phẫu thuật theo dòng, trộn 3 chế độ) đã nằm ở các type **thuần** dùng chung nên
/// ở đây chỉ còn I/O + swap snapshot + phát đúng một thông báo.
///
/// Giữ nguyên mọi bất biến của phân hệ: compile **toàn bộ** file vào staging, có hard error thì
/// **không** ghi file và **không** swap snapshot; sạch thì `write(options: .atomic)` rồi swap dưới
/// `NSLock` và phát đúng **một** `notifyDictionariesDidUpdate(bookId:)`.
///
/// Ranh giới tầng: Service ⇒ **không** `import SwiftUI`, **không** `ToastManager`.
public final class QuickTranslationRuleBookStore: ObservableObject {
    public static let shared = QuickTranslationRuleBookStore()

    /// Trùng tên file với bộ chung — cùng định dạng, chỉ khác thư mục.
    public static let ruleFileName = QuickTranslationRuleStore.ruleFileName

    /// Chỉ giữ snapshot của vài truyện đang mở. Bộ riêng nhỏ nên compile lại rẻ, còn giữ mọi truyện
    /// thì bộ nhớ phình theo số truyện từng đọc.
    private static let maxCachedBooks = 3
    private static let maxStoredIssues = 400
    private static let maxRuleFileBytes = 8 * 1024 * 1024

    /// Chỉ để `@Published` đẩy UI; không đi vào cache key dịch.
    @MainActor @Published public private(set) var revision = 0

    private let lock = NSLock()
    /// Nối tiếp các giao dịch sửa file như store chung, để text đã kiểm revision không bị chen.
    private let mutationLock = NSLock()
    private nonisolated(unsafe) var snapshots: [String: QuickTranslationRuleSnapshot] = [:]
    /// bookId mới dùng đứng **cuối**; phần tử đầu bị loại trước.
    private nonisolated(unsafe) var lruOrder: [String] = []
    private nonisolated(unsafe) var generationCounter = 0

    private init() {}

    // MARK: - File trên máy

    public func ruleFileURL(for bookId: String) -> URL {
        TranslationManager.shared.translateDirectory
            .appendingPathComponent("books")
            .appendingPathComponent(bookId)
            .appendingPathComponent(Self.ruleFileName)
    }

    public func hasRuleFile(for bookId: String) -> Bool {
        FileManager.default.fileExists(atPath: ruleFileURL(for: bookId).path)
    }

    public func currentSourceText(for bookId: String) -> String? {
        try? String(contentsOf: ruleFileURL(for: bookId), encoding: .utf8)
    }

    // MARK: - Snapshot

    /// Snapshot của bộ riêng, compile lazy lần đầu. `nil` khi truyện chưa có file rule riêng.
    public func snapshot(for bookId: String?) -> QuickTranslationRuleSnapshot? {
        guard let bookId, !bookId.isEmpty else { return nil }

        lock.lock()
        if let cached = snapshots[bookId] {
            touch(bookId)
            lock.unlock()
            return cached
        }
        lock.unlock()

        guard let text = currentSourceText(for: bookId) else { return nil }
        return compileAndStore(text: text, bookId: bookId, source: .local)
    }

    /// Snapshot dùng cho một lượt rewrite: `nil` khi công tắc tổng tắt, chưa có file, hoặc file rỗng.
    /// Công tắc tổng là **của cả tính năng rule**, nên bộ riêng cũng phải tôn trọng nó.
    public func activeSnapshot(for bookId: String?) -> QuickTranslationRuleSnapshot? {
        guard QuickTranslationRuleStore.shared.isEnabled else { return nil }
        guard let snapshot = snapshot(for: bookId), !snapshot.rules.isEmpty else { return nil }
        return snapshot
    }

    public func ruleCount(for bookId: String) -> Int {
        snapshot(for: bookId)?.ruleCount ?? 0
    }

    // MARK: - CRUD từng rule

    /// Thêm rule mới; mẫu đã có thì **đè vế phải**, giữ nguyên vị trí dòng — đúng ngữ nghĩa bộ chung.
    /// Truyện chưa có file rule riêng vẫn thêm được: file được tạo mới từ rule đầu tiên.
    public func addOrOverwriteRule(
        pattern: String,
        replacement: String,
        bookId: String
    ) -> QuickTranslationRuleStore.LoadOutcome {
        let key = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return .failure(message: "Mẫu rule không được để trống") }

        return withMutationLock {
            let edit = QuickTranslationRuleFileEditor.upsert(
                pattern: key,
                replacement: replacement,
                in: currentSourceText(for: bookId) ?? ""
            )
            return writeLocked(text: edit.text, bookId: bookId, source: .edited, edit: edit)
        }
    }

    /// Đổi mẫu ⇒ xử như **thêm mẫu mới**, dòng cũ giữ nguyên (đúng `DictionaryCache.updateKey`).
    public func updateRule(
        oldPattern: String,
        newPattern: String,
        replacement: String,
        bookId: String
    ) -> QuickTranslationRuleStore.LoadOutcome {
        let newKey = newPattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newKey.isEmpty else { return .failure(message: "Mẫu rule không được để trống") }

        return withMutationLock {
            guard let current = currentSourceText(for: bookId) else {
                return .failure(message: "Truyện này chưa có bộ rule riêng")
            }
            let edit = QuickTranslationRuleFileEditor.update(
                oldPattern: oldPattern,
                newPattern: newKey,
                replacement: replacement,
                in: current
            )
            return writeLocked(text: edit.text, bookId: bookId, source: .edited, edit: edit)
        }
    }

    /// Xoá đúng hàng đã chọn, kể cả khi file có nhiều rule trùng hoàn toàn mẫu/vế phải.
    /// Nhận **handle UUID** chứ không nhận `sourceLine`: số dòng đổi sau mỗi lần thêm/xoá, dùng nó
    /// làm định danh chính là nguyên nhân crash đã sửa ở 1.3.271.
    public func deleteRule(rowID: UUID, bookId: String) -> QuickTranslationRuleStore.LoadOutcome {
        withMutationLock {
            guard let snapshot = snapshot(for: bookId),
                  let current = currentSourceText(for: bookId) else {
                return .failure(message: "Truyện này chưa có bộ rule riêng")
            }
            guard current.sha256() == snapshot.sourceRevision else {
                return .failure(message: "Bộ rule riêng đã thay đổi ngoài app, hãy tải lại danh sách rồi thử lại")
            }
            guard let row = snapshot.rows.first(where: { $0.id == rowID }),
                  snapshot.rules.indices.contains(row.ruleIndex) else {
                return .failure(message: "Rule đã không còn trong danh sách hiện tại")
            }

            let rule = snapshot.rules[row.ruleIndex]
            guard let edit = QuickTranslationRuleFileEditor.delete(
                sourceLine: rule.sourceLine,
                expectedPattern: rule.pattern,
                expectedReplacement: rule.replacement,
                from: current
            ) else {
                return .failure(message: "Không tìm thấy đúng rule đã chọn trong file")
            }
            return writeLocked(text: edit.text, bookId: bookId, source: .edited, edit: edit)
        }
    }

    // MARK: - Nhập / xuất cả bộ

    /// Nhập file rule cho **một truyện**. Cùng 3 chế độ và cùng validate-then-swap như bộ chung.
    public func importRules(
        text: String,
        mode: DataImportMode = .replaceAll,
        bookId: String,
        notifiesObservers: Bool = true
    ) -> QuickTranslationRuleStore.LoadOutcome {
        withMutationLock {
            let merged: String
            if mode == .replaceAll {
                merged = text
            } else {
                merged = QuickTranslationRuleFileEditor.merge(
                    current: currentSourceText(for: bookId) ?? "",
                    imported: text,
                    mode: mode
                )
            }
            return writeLocked(
                text: merged,
                bookId: bookId,
                source: .imported,
                notifiesObservers: notifiesObservers
            )
        }
    }

    /// Xoá cả bộ rule riêng của một truyện khỏi máy: truyện đó quay về dùng thuần bộ chung.
    @discardableResult
    public func deleteRules(for bookId: String) -> Bool {
        withMutationLock {
            let existed = hasRuleFile(for: bookId)
            try? FileManager.default.removeItem(at: ruleFileURL(for: bookId))

            lock.lock()
            snapshots.removeValue(forKey: bookId)
            lruOrder.removeAll { $0 == bookId }
            lock.unlock()

            AppLogger.shared.log("🗑️ [QuickTranslateRule] Đã xoá bộ rule riêng của một truyện")
            notifyChange(bookId: bookId)
            return existed
        }
    }

    /// Bỏ snapshot đã cache. Gọi khi đổi nguồn (bookId đổi) hoặc sau khi khôi phục backup.
    public func invalidate(bookId: String? = nil) {
        lock.lock()
        if let bookId {
            snapshots.removeValue(forKey: bookId)
            lruOrder.removeAll { $0 == bookId }
        } else {
            snapshots.removeAll()
            lruOrder.removeAll()
        }
        lock.unlock()
        bumpRevision()
    }

    // MARK: - Ghi

    func withMutationLock<T>(_ operation: () -> T) -> T {
        mutationLock.lock()
        defer { mutationLock.unlock() }
        return operation()
    }

    /// Validate-then-swap: compile toàn bộ vào staging trước, chỉ khi sạch hard error mới ghi file.
    private func writeLocked(
        text: String,
        bookId: String,
        source: QuickTranslationRuleSnapshot.Source,
        notifiesObservers: Bool = true,
        edit: QuickTranslationRuleFileEditor.Edit? = nil
    ) -> QuickTranslationRuleStore.LoadOutcome {
        guard text.utf8.count <= Self.maxRuleFileBytes else {
            return .failure(message: "File rule vượt 8 MB, gần như chắc chắn không phải bộ rule")
        }

        let staged = QuickTranslationRuleCompiler.compile(
            QuickTranslationRuleParser.parse(text),
            scopeRank: 0
        )
        if staged.hasHardError {
            return .rejected(issues: staged.issues.filter { $0.severity == .hard })
        }

        let url = ruleFileURL(for: bookId)
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data(text.utf8).write(to: url, options: .atomic)
        } catch {
            return .failure(message: "Không ghi được file rule riêng: \(error.localizedDescription)")
        }

        let snapshot = compileAndStore(
            text: text,
            bookId: bookId,
            source: source,
            precompiled: staged,
            edit: edit
        )
        if notifiesObservers {
            notifyChange(bookId: bookId)
        } else {
            bumpRevision()
        }
        let warningCount = snapshot?.warningCount ?? 0
        return .success(ruleCount: snapshot?.ruleCount ?? 0, warningCount: warningCount)
    }

    // MARK: - Phụ trợ

    /// Compile rồi đặt vào cache LRU. Trả `nil` chỉ khi compile có hard error (caller đã chặn trước).
    @discardableResult
    private func compileAndStore(
        text: String,
        bookId: String,
        source: QuickTranslationRuleSnapshot.Source,
        precompiled: QuickTranslationRuleCompiler.Result? = nil,
        edit: QuickTranslationRuleFileEditor.Edit? = nil
    ) -> QuickTranslationRuleSnapshot? {
        let compiled = precompiled ?? QuickTranslationRuleCompiler.compile(
            QuickTranslationRuleParser.parse(text),
            scopeRank: 0
        )
        guard !compiled.hasHardError else { return nil }

        let warnings = compiled.issues.filter { $0.severity != .hard }

        lock.lock()
        generationCounter += 1
        let generation = generationCounter
        let previous = snapshots[bookId]
        let snapshot = QuickTranslationRuleSnapshot(
            generation: generation,
            source: source,
            sourceHash: String(text.md5().prefix(8)),
            sourceRevision: text.sha256(),
            rules: compiled.rules,
            rowIDs: QuickTranslationRuleStore.rowIDs(
                for: compiled.rules,
                previousSnapshot: previous,
                edit: edit
            ),
            issues: Array(warnings.prefix(Self.maxStoredIssues)),
            warningCount: warnings.count
        )
        snapshots[bookId] = snapshot
        touch(bookId)
        evictIfNeeded()
        lock.unlock()

        AppLogger.shared.log(
            "🔤 [QuickTranslateRule] Bộ riêng: nạp \(snapshot.ruleCount) rule"
            + " (\(source.label), hash \(snapshot.sourceHash), \(warnings.count) cảnh báo, gen \(generation))"
        )
        return snapshot
    }

    /// Gọi khi đã giữ `lock`.
    private func touch(_ bookId: String) {
        lruOrder.removeAll { $0 == bookId }
        lruOrder.append(bookId)
    }

    /// Gọi khi đã giữ `lock`.
    private func evictIfNeeded() {
        while lruOrder.count > Self.maxCachedBooks, let oldest = lruOrder.first {
            lruOrder.removeFirst()
            snapshots.removeValue(forKey: oldest)
        }
    }

    /// Đúng **một** lời gọi: `notifyDictionariesDidUpdate(bookId:)` đã tự
    /// `QuickTranslationRuleEngine.clearCache()` + bump generation của đúng truyện đó qua
    /// `TranslateUtils.invalidateCache(bookId:)`, rồi post `.translationDictionariesDidUpdate`.
    private func notifyChange(bookId: String) {
        bumpRevision()
        TranslationManager.shared.notifyDictionariesDidUpdate(
            bookId: bookId,
            scope: .config(bookId: bookId)
        )
    }

    private func bumpRevision() {
        Task { @MainActor in
            self.revision += 1
        }
    }
}
