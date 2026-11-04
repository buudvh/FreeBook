import Foundation
import Combine

/// Chủ sở hữu **bộ rule tên chương** (`translate/QuickTranslateChapterRules.txt`, 1.3.683), song song với
/// `QuickTranslationRuleStore` (bộ chung) và `QuickTranslationRuleBookStore` (bộ riêng của truyện).
///
/// Bộ này dùng chung cho mọi truyện nhưng **chỉ** vào cuộc khi dịch tên chương: engine chỉ trộn nó khi cờ
/// `TranslationReadContext.appliesChapterTitleRules` bật (đặt ở `TranslateUtils.translateChapterTitle`).
/// Thứ tự ưu tiên khi trùng mọi tiêu chí khác: riêng > tên chương > chung (`QuickTranslationRuleScope.rank`).
///
/// Vì sao là type riêng: store chung đã chạm trần 400 dòng và hard-code một file; phần khó (parse, compile,
/// chuẩn hoá records, trộn 3 chế độ) đã nằm ở các type **thuần** dùng chung nên ở đây chỉ còn I/O + swap
/// snapshot + phát thông báo — cùng khuôn với `QuickTranslationRuleBookStore`.
///
/// Nạp **lười**: lần đầu có ai đọc `currentSnapshot` (thường là `TranslationReadContext.capture`). Lần nạp đầu
/// **không** đổi `generation` — nội dung trên đĩa không đổi, nên khoá cache dịch tính trước đó vẫn đúng.
/// `generation` chỉ tăng khi bộ rule thật sự đổi (thêm/sửa/xoá/nhập/xoá cả bộ/nạp lại).
///
/// Ranh giới tầng: Service ⇒ **không** `import SwiftUI`, **không** `ToastManager`.
public final class QuickTranslationRuleChapterStore: ObservableObject {
    public static let shared = QuickTranslationRuleChapterStore()

    /// Khác tên với file bộ chung vì cùng nằm ở `translate/`.
    public static let ruleFileName = "QuickTranslateChapterRules.txt"

    private static let maxStoredIssues = 400
    private static let maxRuleFileBytes = 8 * 1024 * 1024

    /// Chỉ để `@Published` đẩy UI; không đi vào cache key dịch (cache key dùng `generation`).
    @MainActor @Published public private(set) var revision = 0

    private let lock = NSLock()
    /// Nối tiếp các giao dịch sửa file như hai store kia, để text đã đọc không bị một CRUD khác chen vào.
    private let mutationLock = NSLock()
    private nonisolated(unsafe) var snapshot: QuickTranslationRuleSnapshot?
    private nonisolated(unsafe) var isLoaded = false
    private nonisolated(unsafe) var generationCounter = 0

    private init() {}

    // MARK: - File trên máy

    public var ruleFileURL: URL {
        TranslationManager.shared.translateDirectory.appendingPathComponent(Self.ruleFileName)
    }

    public var hasRuleFile: Bool {
        FileManager.default.fileExists(atPath: ruleFileURL.path)
    }

    public func currentSourceText() -> String? {
        try? String(contentsOf: ruleFileURL, encoding: .utf8)
    }

    // MARK: - Trạng thái cho pipeline dịch

    /// Đi vào `TranslateUtils.translationGenerationToken`. **Chỉ** đọc bộ đếm dưới khoá: hàm đó gọi tới đây
    /// khi đang giữ `cacheLock` của `TranslateUtils`, nên tuyệt đối không nạp file hay compile ở đây.
    public var generation: Int {
        lock.lock()
        defer { lock.unlock() }
        return generationCounter
    }

    /// Snapshot của bộ tên chương, nạp lười lần đầu. `nil` khi máy chưa có file (hoặc file rỗng).
    public var currentSnapshot: QuickTranslationRuleSnapshot? {
        lock.lock()
        if isLoaded {
            defer { lock.unlock() }
            return snapshot
        }
        lock.unlock()
        return loadFromDisk()
    }

    /// Snapshot dùng cho một lượt rewrite: `nil` khi công tắc tổng tắt, chưa có file, hoặc file rỗng.
    /// Công tắc tổng là **của cả tính năng rule**, nên bộ tên chương cũng phải tôn trọng nó.
    public var activeSnapshot: QuickTranslationRuleSnapshot? {
        guard QuickTranslationRuleStore.shared.isEnabled else { return nil }
        guard let snapshot = currentSnapshot, !snapshot.rules.isEmpty else { return nil }
        return snapshot
    }

    public var ruleCount: Int {
        currentSnapshot?.ruleCount ?? 0
    }

    // MARK: - CRUD từng rule

    /// Thêm rule mới; mẫu đã có thì **đè vế phải**, giữ nguyên vị trí dòng — đúng ngữ nghĩa hai bộ kia.
    /// Máy chưa có file vẫn thêm được: file được tạo mới từ rule đầu tiên.
    public func addOrOverwriteRule(pattern: String, replacement: String) -> QuickTranslationRuleStore.LoadOutcome {
        let key = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return .failure(message: "Mẫu rule không được để trống") }
        return withMutationLock {
            let records = QuickTranslationRuleRecordStore.upsert(
                pattern: key,
                replacement: replacement,
                in: QuickTranslationRuleRecordStore.parseRecords(from: currentSourceText() ?? "")
            )
            return writeLocked(records: records, source: .edited)
        }
    }

    /// Sửa rule **thay chỗ** dòng `oldPattern` ("Thay rule cũ", 1.3.705) — như `QuickTranslationRuleStore.updateRule`.
    public func updateRule(
        oldPattern: String,
        newPattern: String,
        replacement: String
    ) -> QuickTranslationRuleStore.LoadOutcome {
        let newKey = newPattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newKey.isEmpty else { return .failure(message: "Mẫu rule không được để trống") }
        return withMutationLock {
            let records = QuickTranslationRuleRecordStore.replacing(
                oldPattern: oldPattern,
                pattern: newKey,
                replacement: replacement,
                in: QuickTranslationRuleRecordStore.parseRecords(from: currentSourceText() ?? "")
            )
            return writeLocked(records: records, source: .edited)
        }
    }

    /// Xoá rule theo mẫu bên trái dấu `=`. File được chuẩn hoá first-wins nên key này là duy nhất.
    public func deleteRule(pattern: String) -> QuickTranslationRuleStore.LoadOutcome {
        let key = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return .failure(message: "Mẫu rule không được để trống") }
        return withMutationLock {
            let records = QuickTranslationRuleRecordStore.parseRecords(from: currentSourceText() ?? "")
            let updated = QuickTranslationRuleRecordStore.removing(pattern: key, from: records)
            guard updated.count != records.count else {
                return .failure(message: "Không tìm thấy đúng rule đã chọn trong file")
            }
            return writeLocked(records: updated, source: .edited)
        }
    }

    /// Xoá nhiều rule cùng lúc theo tập mẫu. Không fail nếu có mẫu stale không tồn tại trong file.
    public func deleteRules(patterns: Set<String>) -> QuickTranslationRuleStore.LoadOutcome {
        guard !patterns.isEmpty else { return .success(ruleCount: ruleCount, warningCount: 0) }
        return withMutationLock {
            let records = QuickTranslationRuleRecordStore.parseRecords(from: currentSourceText() ?? "")
            let updated = records.filter { !patterns.contains($0.pattern) }
            return writeLocked(records: updated, source: .edited)
        }
    }

    // MARK: - Nhập / xoá cả bộ

    /// Nhập file rule tên chương. Cùng 3 chế độ và cùng chính sách canonical như hai bộ kia.
    ///
    /// `notifiesObservers: false` dành cho **khôi phục backup**: `generation` vẫn tăng (cache dịch tự đổi
    /// khoá), chỉ không phát thông báo — bên gọi phát một lần ở cuối lượt.
    public func importRules(
        text: String,
        mode: DataImportMode = .replaceAll,
        notifiesObservers: Bool = true
    ) -> QuickTranslationRuleStore.LoadOutcome {
        guard text.utf8.count <= Self.maxRuleFileBytes else {
            return .failure(message: "File rule vượt 8 MB, gần như chắc chắn không phải bộ rule")
        }
        return withMutationLock {
            let imported = QuickTranslationRuleRecordStore.parseRecords(from: text)
            let records = mode == .replaceAll
                ? imported
                : QuickTranslationRuleRecordStore.merge(
                    existing: QuickTranslationRuleRecordStore.parseRecords(from: currentSourceText() ?? ""),
                    imported: imported,
                    mode: mode
                )
            return writeLocked(records: records, source: .imported, notifiesObservers: notifiesObservers)
        }
    }

    /// Xoá cả bộ rule tên chương khỏi máy: tên chương quay về dịch bằng bộ riêng + bộ chung + từ điển.
    @discardableResult
    public func deleteRules() -> Bool {
        withMutationLock {
            let existed = hasRuleFile
            try? FileManager.default.removeItem(at: ruleFileURL)
            replaceSnapshot(nil)
            AppLogger.shared.log("🗑️ [QuickTranslateRule] Đã xoá bộ rule tên chương khỏi máy")
            notifyChange()
            return existed
        }
    }

    // MARK: - Ghi

    private func withMutationLock<T>(_ operation: () -> T) -> T {
        mutationLock.lock()
        defer { mutationLock.unlock() }
        return operation()
    }

    /// Ghi canonical records rồi swap snapshot; rule hỏng bị bỏ qua như VP/Name custom.
    private func writeLocked(
        records: [QuickTranslationRuleRecordStore.Record],
        source: QuickTranslationRuleSnapshot.Source,
        notifiesObservers: Bool = true
    ) -> QuickTranslationRuleStore.LoadOutcome {
        let prepared = QuickTranslationRuleRecordStore.validRecords(
            from: records,
            scopeRank: QuickTranslationRuleScope.chapterTitleRank
        )
        let text = QuickTranslationRuleRecordStore.serialize(prepared.records)
        guard text.utf8.count <= Self.maxRuleFileBytes else {
            return .failure(message: "File rule vượt 8 MB, gần như chắc chắn không phải bộ rule")
        }

        let url = ruleFileURL
        let newSnapshot: QuickTranslationRuleSnapshot?
        if prepared.records.isEmpty {
            try? FileManager.default.removeItem(at: url)
            newSnapshot = nil
        } else {
            do {
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try Data(text.utf8).write(to: url, options: .atomic)
            } catch {
                return .failure(message: "Không ghi được file rule tên chương: \(error.localizedDescription)")
            }
            // Mang trước số `generation` mà `replaceSnapshot` sắp tăng tới (chỉ để log/khoá memo dễ đọc).
            newSnapshot = makeSnapshot(text: text, source: source, compiled: prepared.compiled, generation: generation + 1)
        }

        replaceSnapshot(newSnapshot)
        if notifiesObservers {
            notifyChange()
        } else {
            bumpRevision()
        }
        return .success(ruleCount: newSnapshot?.ruleCount ?? 0, warningCount: newSnapshot?.warningCount ?? 0)
    }

    // MARK: - Phụ trợ

    /// Nạp lần đầu từ đĩa. Chỉ ghi vào store khi chưa có lượt ghi nào chen vào trước (`isLoaded` vẫn
    /// `false`); ngược lại bản vừa đọc có thể đã cũ nên bỏ đi và trả snapshot của lượt ghi.
    private func loadFromDisk() -> QuickTranslationRuleSnapshot? {
        let loaded = currentSourceText().flatMap { text -> QuickTranslationRuleSnapshot? in
            let compiled = QuickTranslationRuleCompiler.compile(
                QuickTranslationRuleParser.parse(text),
                scopeRank: QuickTranslationRuleScope.chapterTitleRank
            )
            guard !compiled.rules.isEmpty else { return nil }
            return makeSnapshot(text: text, source: .local, compiled: compiled, generation: generation)
        }

        lock.lock()
        defer { lock.unlock() }
        guard !isLoaded else { return snapshot }
        snapshot = loaded
        isLoaded = true
        return loaded
    }

    /// Dựng snapshot; bộ đếm `generation` của store chỉ tăng ở `replaceSnapshot`, cùng lúc swap snapshot.
    private func makeSnapshot(
        text: String,
        source: QuickTranslationRuleSnapshot.Source,
        compiled: QuickTranslationRuleCompiler.Result,
        generation: Int
    ) -> QuickTranslationRuleSnapshot {
        let warnings = compiled.issues.filter { $0.severity != .hard }
        let snapshot = QuickTranslationRuleSnapshot(
            generation: generation,
            source: source,
            sourceHash: String(text.md5().prefix(8)),
            rules: compiled.rules,
            issues: Array(warnings.prefix(Self.maxStoredIssues)),
            warningCount: warnings.count
        )
        AppLogger.shared.log(
            "🔤 [QuickTranslateRule] Bộ tên chương: nạp \(snapshot.ruleCount) rule"
            + " (\(source.label), hash \(snapshot.sourceHash), \(warnings.count) cảnh báo, gen \(generation))"
        )
        return snapshot
    }

    /// Đổi snapshot = bộ rule đã đổi ⇒ tăng `generation` để mọi cache dịch tính trước đó trượt khoá.
    private func replaceSnapshot(_ newSnapshot: QuickTranslationRuleSnapshot?) {
        lock.lock()
        generationCounter += 1
        snapshot = newSnapshot
        isLoaded = true
        lock.unlock()
    }

    /// Bộ tên chương không thuộc truyện nào ⇒ dọn cache dịch toàn cục rồi phát **một** thông báo rule đã
    /// đổi để Reader/TTS dựng lại. Gọi **ngoài** `lock` của store.
    private func notifyChange() {
        bumpRevision()
        TranslateUtils.invalidateCache(bookId: nil)
        TranslationManager.shared.notifyRulesDidUpdate()
    }

    private func bumpRevision() {
        Task { @MainActor in
            self.revision += 1
        }
    }
}
