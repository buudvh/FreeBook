import Foundation
import Combine

/// Chủ sở hữu **bộ rule riêng của từng truyện** (`translate/books/<bookId>/QuickTranslateRules.txt`),
/// song song với `QuickTranslationRuleStore` là chủ bộ chung.
///
/// Vì sao là type riêng chứ không tổng quát hoá store chung: store chung đã sát trần 400 dòng của
/// `check_architecture.py` và mọi method của nó đều hard-code một file duy nhất. Toàn bộ phần khó
/// (parse, compile, chuẩn hoá records, trộn 3 chế độ) đã nằm ở các type **thuần** dùng chung nên
/// ở đây chỉ còn I/O + swap snapshot + phát đúng một thông báo.
///
/// File rule riêng dùng cùng chính sách với VP/Name custom: dòng không hợp lệ bị bỏ qua, trùng mẫu lấy
/// dòng đầu và mọi lần ghi đều sinh lại một file `pattern = replacement` sạch.
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
            let records = QuickTranslationRuleRecordStore.upsert(
                pattern: key,
                replacement: replacement,
                in: QuickTranslationRuleRecordStore.parseRecords(from: currentSourceText(for: bookId) ?? "")
            )
            return writeLocked(records: records, bookId: bookId, source: .edited)
        }
    }

    /// Đổi mẫu ⇒ xử như **thêm mẫu mới**, dòng cũ giữ nguyên (đúng `DictionaryCache.updateKey`).
    public func updateRule(
        oldPattern _: String,
        newPattern: String,
        replacement: String,
        bookId: String
    ) -> QuickTranslationRuleStore.LoadOutcome {
        let newKey = newPattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newKey.isEmpty else { return .failure(message: "Mẫu rule không được để trống") }

        return withMutationLock {
            let records = QuickTranslationRuleRecordStore.upsert(
                pattern: newKey,
                replacement: replacement,
                in: QuickTranslationRuleRecordStore.parseRecords(from: currentSourceText(for: bookId) ?? "")
            )
            return writeLocked(records: records, bookId: bookId, source: .edited)
        }
    }

    /// Xoá rule theo mẫu bên trái dấu `=`. File được chuẩn hoá first-wins nên key này là duy nhất.
    public func deleteRule(pattern: String, bookId: String) -> QuickTranslationRuleStore.LoadOutcome {
        let key = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return .failure(message: "Mẫu rule không được để trống") }
        withMutationLock {
            let current = currentSourceText(for: bookId) ?? ""
            let records = QuickTranslationRuleRecordStore.parseRecords(from: current)
            let updated = QuickTranslationRuleRecordStore.removing(pattern: key, from: records)
            guard updated.count != records.count else {
                return .failure(message: "Không tìm thấy đúng rule đã chọn trong file")
            }
            return writeLocked(records: updated, bookId: bookId, source: .edited)
        }
    }

    // MARK: - Nhập / xuất cả bộ

    /// Nhập file rule cho **một truyện**. Cùng 3 chế độ và cùng chính sách canonical như bộ chung.
    public func importRules(
        text: String,
        mode: DataImportMode = .replaceAll,
        bookId: String,
        notifiesObservers: Bool = true
    ) -> QuickTranslationRuleStore.LoadOutcome {
        withMutationLock {
            let imported = QuickTranslationRuleRecordStore.parseRecords(from: text)
            let records = mode == .replaceAll
                ? imported
                : QuickTranslationRuleRecordStore.merge(
                    existing: QuickTranslationRuleRecordStore.parseRecords(from: currentSourceText(for: bookId) ?? ""),
                    imported: imported,
                    mode: mode
                )
            return writeLocked(
                records: records,
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

    /// Ghi canonical records rồi swap snapshot; rule hỏng bị bỏ qua như VP/Name custom.
    private func writeLocked(
        records: [QuickTranslationRuleRecordStore.Record],
        bookId: String,
        source: QuickTranslationRuleSnapshot.Source,
        notifiesObservers: Bool = true
    ) -> QuickTranslationRuleStore.LoadOutcome {
        let prepared = QuickTranslationRuleRecordStore.validRecords(from: records, scopeRank: 0)
        let text = QuickTranslationRuleRecordStore.serialize(prepared.records)

        guard text.utf8.count <= Self.maxRuleFileBytes else {
            return .failure(message: "File rule vượt 8 MB, gần như chắc chắn không phải bộ rule")
        }

        let url = ruleFileURL(for: bookId)
        if prepared.records.isEmpty {
            try? FileManager.default.removeItem(at: url)
            lock.lock()
            snapshots.removeValue(forKey: bookId)
            lruOrder.removeAll { $0 == bookId }
            lock.unlock()
            if notifiesObservers {
                notifyChange(bookId: bookId)
            } else {
                bumpRevision()
            }
            return .success(ruleCount: 0, warningCount: 0)
        }

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
            precompiled: prepared.compiled
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

    /// Compile rồi đặt vào cache LRU. Luồng canonical đã bỏ rule lỗi nặng trước khi tới đây.
    @discardableResult
    private func compileAndStore(
        text: String,
        bookId: String,
        source: QuickTranslationRuleSnapshot.Source,
        precompiled: QuickTranslationRuleCompiler.Result? = nil
    ) -> QuickTranslationRuleSnapshot? {
        let compiled = precompiled ?? QuickTranslationRuleCompiler.compile(
            QuickTranslationRuleParser.parse(text),
            scopeRank: 0
        )

        let warnings = compiled.issues.filter { $0.severity != .hard }

        lock.lock()
        generationCounter += 1
        let generation = generationCounter
        let snapshot = QuickTranslationRuleSnapshot(
            generation: generation,
            source: source,
            sourceHash: String(text.md5().prefix(8)),
            rules: compiled.rules,
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
