import Foundation
import Combine

/// Chủ sở hữu duy nhất của bộ rule dịch: tải/nhập file, chuẩn hoá records **atomically**, giữ
/// `generation` cho cache dịch, và cấp dữ liệu cho màn hình quản lý.
///
/// Bộ rule **không** đi kèm app. Nó nằm ở `translate/QuickTranslateRules.txt` và có đúng hai đường
/// vào: nút tải về (HuggingFace, cùng dataset với VietPhrase/PhienAm) hoặc người dùng nhập file.
/// Chưa có file thì `activeSnapshot` trả `nil` và pipeline dịch chạy y như trước khi có tính năng này.
///
/// Ranh giới tầng: đây là Service nên **không** `import SwiftUI` và **không** gọi `ToastManager` —
/// View gọi hàm ở đây rồi tự phát toast.
public final class QuickTranslationRuleStore: ObservableObject {
    public static let shared = QuickTranslationRuleStore()

    public static let enabledKey = "isQuickTranslateRuleEnabled"
    /// Tên file trên máy **và** tên file trên HuggingFace — giữ trùng nhau để người dùng tải tay rồi
    /// nhập vào cũng khớp.
    public static let ruleFileName = "QuickTranslateRules.txt"
    /// Cùng dataset với `TranslationManager.downloadDefaultDictionaries`.
    public static let downloadURLString =
        "https://huggingface.co/datasets/raikiri1498/vietpharse/resolve/main/QuickTranslateRules.txt"

    private static let maxStoredIssues = 400
    /// Chặn file lạ quá lớn trước khi parse: bộ rule lớn nhất đã biết (`Rule_new.txt`) là 690 KB.
    private static let maxRuleFileBytes = 8 * 1024 * 1024

    /// Trạng thái cho UI. Cập nhật trên MainActor như `JunkFilterManager`.
    public struct Status: Sendable {
        public var isLoaded = false
        public var sourceLabel = "Chưa có bộ rule"
        /// Máy đang có file rule hay không — quyết định nút Xuất/Xoá có bật.
        public var hasFile = false
        public var ruleCount = 0
        public var warningCount = 0
        public var sourceHash = ""
        public var loadedAt: Date? = nil
        public var issues: [QuickTranslationRuleIssue] = []
        /// Dòng rule chạm cap backtracking ở runtime (`RULE_TOO_COMPLEX`).
        public var complexRuleLines: [Int] = []
    }

    public enum LoadOutcome: Sendable {
        case success(ruleCount: Int, warningCount: Int)
        /// Legacy outcome để caller cũ vẫn xử lý được; luồng canonical hiện bỏ dòng hỏng thay vì reject cả file.
        case rejected(issues: [QuickTranslationRuleIssue])
        case failure(message: String)
    }

    @MainActor @Published public private(set) var status = Status()
    @MainActor @Published public private(set) var isDownloading = false

    private let lock = NSLock()
    /// Nối tiếp các giao dịch sửa file để text đã kiểm revision không bị một CRUD nội bộ khác chen vào.
    private let mutationLock = NSLock()
    private nonisolated(unsafe) var snapshot: QuickTranslationRuleSnapshot?
    private nonisolated(unsafe) var generationCounter = 0
    private nonisolated(unsafe) var didPrewarm = false
    private nonisolated(unsafe) var complexRuleLines: Set<Int> = []

    private init() {}

    // MARK: - Trạng thái cho pipeline dịch

    /// Mặc định **bật**. Repo không có `UserDefaults.register(defaults:)` ở đâu cả, nên
    /// `bool(forKey:)` sẽ trả `false` khi khoá chưa tồn tại — phải đọc qua `object(forKey:)`.
    public var isEnabled: Bool {
        UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true
    }

    /// Thẻ đi vào cache key dịch: công tắc tổng, cấu hình token và generation của snapshot.
    public var cacheTag: String {
        lock.lock()
        let generation = generationCounter
        lock.unlock()
        let tokenSignature = QuickTranslationRuleTokenSettings.currentConfiguration().signature
        return "\(isEnabled ? 1 : 0):\(tokenSignature):\(generation)"
    }

    public var currentSnapshot: QuickTranslationRuleSnapshot? {
        lock.lock()
        defer { lock.unlock() }
        return snapshot
    }

    /// Snapshot dùng cho một lượt rewrite: `nil` khi công tắc tắt, chưa tải bộ rule, hoặc file rỗng.
    public var activeSnapshot: QuickTranslationRuleSnapshot? {
        guard isEnabled else { return nil }
        lock.lock()
        defer { lock.unlock() }
        guard let snapshot = snapshot, !snapshot.rules.isEmpty else { return nil }
        return snapshot
    }

    // MARK: - File trên máy

    public var ruleFileURL: URL {
        TranslationManager.shared.translateDirectory.appendingPathComponent(Self.ruleFileName)
    }

    public var hasRuleFile: Bool {
        FileManager.default.fileExists(atPath: ruleFileURL.path)
    }

    /// Văn bản của bộ đang chạy, để người dùng lấy ra sửa ngoài app.
    public func currentSourceText() -> String? {
        try? String(contentsOf: ruleFileURL, encoding: .utf8)
    }

    func withMutationLock<T>(_ operation: () -> T) -> T {
        mutationLock.lock()
        defer { mutationLock.unlock() }
        return operation()
    }

    // MARK: - Nạp

    /// Gọi một lần khi khởi động, **trước** khi lần dịch đầu chạy. Nạp lại nhiều lần là no-op.
    public func prewarm() {
        lock.lock()
        let alreadyDone = didPrewarm
        didPrewarm = true
        lock.unlock()
        guard !alreadyDone else { return }
        // Lần nạp đầu không phát thông báo: chưa có cache dịch nào để dọn và chưa có Reader/TTS nào
        // đang mở, phát ra chỉ làm bump generation vô ích lúc khởi động.
        _ = load(notifiesObservers: false)
    }

    /// Nạp lại từ file trên máy. Chưa có file thì đây **không** phải lỗi cần báo động: tính năng chỉ
    /// đơn giản là chưa được bật bằng dữ liệu.
    @discardableResult
    public func load(notifiesObservers: Bool = true) -> LoadOutcome {
        withMutationLock {
            guard let text = try? String(contentsOf: ruleFileURL, encoding: .utf8) else {
                publish(Status())
                return .failure(message: "Chưa có bộ rule nào trên máy")
            }
            return apply(text: text, source: .local, notifiesObservers: notifiesObservers)
        }
    }

    /// Nhập/ghi bộ rule: parse records, bỏ dòng hỏng, compile **toàn bộ vào staging**, rồi ghi lại TXT
    /// canonical và swap snapshot.
    ///
    /// `mode` mặc định `.replaceAll` để hai caller không có UI chọn chế độ — nút tải bộ mặc định và
    /// khôi phục backup — giữ đúng hành vi cũ. Trộn xong thì validate **toàn bộ** kết quả, không chỉ
    /// phần mới: cảnh báo của rule cũ vẫn cần hiện trong snapshot sau khi file được chuẩn hoá.
    ///
    /// `notifiesObservers: false` dành riêng cho **khôi phục backup** để caller phát một thông báo
    /// tổng ở cuối lượt.
    public func importRules(
        text: String,
        source: QuickTranslationRuleSnapshot.Source = .imported,
        mode: DataImportMode = .replaceAll,
        notifiesObservers: Bool = true
    ) -> LoadOutcome {
        withMutationLock {
            importRulesLocked(
                text: text,
                source: source,
                mode: mode,
                notifiesObservers: notifiesObservers
            )
        }
    }

    /// Gọi khi đã giữ `mutationLock`; mọi thao tác đi qua key nghiệp vụ là pattern.
    func importRulesLocked(
        text: String,
        source: QuickTranslationRuleSnapshot.Source,
        mode: DataImportMode = .replaceAll,
        notifiesObservers: Bool = true
    ) -> LoadOutcome {
        guard text.utf8.count <= Self.maxRuleFileBytes else {
            return .failure(message: "File rule vượt 8 MB, gần như chắc chắn không phải bộ rule")
        }

        let imported = QuickTranslationRuleRecordStore.parseRecords(from: text)
        let records: [QuickTranslationRuleRecordStore.Record]
        if mode == .replaceAll {
            records = imported
        } else {
            records = QuickTranslationRuleRecordStore.merge(
                existing: QuickTranslationRuleRecordStore.parseRecords(from: currentSourceText() ?? ""),
                imported: imported,
                mode: mode
            )
        }

        return writeRecordsLocked(records, source: source, notifiesObservers: notifiesObservers)
    }

    func writeRecordsLocked(
        _ records: [QuickTranslationRuleRecordStore.Record],
        source: QuickTranslationRuleSnapshot.Source,
        notifiesObservers: Bool = true
    ) -> LoadOutcome {
        let prepared = QuickTranslationRuleRecordStore.validRecords(from: records, scopeRank: 1)
        let text = QuickTranslationRuleRecordStore.serialize(prepared.records)

        guard text.utf8.count <= Self.maxRuleFileBytes else {
            return .failure(message: "File rule vượt 8 MB, gần như chắc chắn không phải bộ rule")
        }

        if prepared.records.isEmpty {
            try? FileManager.default.removeItem(at: ruleFileURL)
            lock.lock()
            generationCounter += 1
            snapshot = nil
            complexRuleLines.removeAll()
            lock.unlock()
            publish(Status())
            if notifiesObservers {
                invalidateTranslationCaches()
            }
            return .success(ruleCount: 0, warningCount: 0)
        }

        do {
            try FileManager.default.createDirectory(
                at: ruleFileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data(text.utf8).write(to: ruleFileURL, options: .atomic)
        } catch {
            return .failure(message: "Không ghi được file rule: \(error.localizedDescription)")
        }
        return apply(
            text: text,
            source: source,
            precompiled: prepared.compiled,
            notifiesObservers: notifiesObservers
        )
    }

    /// Tải bộ rule mặc định từ HuggingFace rồi đi tiếp bằng đúng đường `importRules`.
    public func downloadDefaultRules() async -> LoadOutcome {
        guard let url = URL(string: Self.downloadURLString) else {
            return .failure(message: "Địa chỉ tải bộ rule không hợp lệ")
        }

        await setDownloading(true)
        let outcome = await fetchRules(from: url)
        await setDownloading(false)
        return outcome
    }

    private func fetchRules(from url: URL) async -> LoadOutcome {
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                return .failure(message: "Máy chủ trả về mã \(http.statusCode)")
            }
            guard data.count <= Self.maxRuleFileBytes else {
                return .failure(message: "File tải về vượt 8 MB")
            }
            guard let text = String(data: data, encoding: .utf8) else {
                return .failure(message: "File tải về không phải văn bản UTF-8")
            }
            AppLogger.shared.log("⬇️ [QuickTranslateRule] Đã tải \(data.count) byte bộ rule từ HuggingFace")
            return importRules(text: text, source: .downloaded)
        } catch {
            return .failure(message: "Không tải được bộ rule: \(error.localizedDescription)")
        }
    }

    /// Xoá bộ rule khỏi máy: pipeline dịch quay về đúng hành vi khi chưa có rule.
    @discardableResult
    public func deleteRules() -> Bool {
        withMutationLock {
            let existed = hasRuleFile
            try? FileManager.default.removeItem(at: ruleFileURL)

            lock.lock()
            generationCounter += 1
            snapshot = nil
            complexRuleLines.removeAll()
            lock.unlock()

            publish(Status())
            invalidateTranslationCaches()
            AppLogger.shared.log("🗑️ [QuickTranslateRule] Đã xoá bộ rule dịch khỏi máy")
            return existed
        }
    }

    private func apply(
        text: String,
        source: QuickTranslationRuleSnapshot.Source,
        precompiled: QuickTranslationRuleCompiler.Result? = nil,
        notifiesObservers: Bool = true
    ) -> LoadOutcome {
        let compiled = precompiled ?? QuickTranslationRuleCompiler.compile(QuickTranslationRuleParser.parse(text))

        let warnings = compiled.issues.filter { $0.severity != .hard }
        lock.lock()
        generationCounter += 1
        let generation = generationCounter
        complexRuleLines.removeAll()
        let newSnapshot = QuickTranslationRuleSnapshot(
            generation: generation,
            source: source,
            sourceHash: String(text.md5().prefix(8)),
            rules: compiled.rules,
            issues: Array(warnings.prefix(Self.maxStoredIssues)),
            warningCount: warnings.count
        )
        snapshot = newSnapshot
        lock.unlock()

        publish(makeStatus(from: newSnapshot))
        if notifiesObservers {
            invalidateTranslationCaches()
        }
        AppLogger.shared.log(
            "🔤 [QuickTranslateRule] Nạp \(newSnapshot.ruleCount) rule (\(source.label),"
            + " hash \(newSnapshot.sourceHash), \(warnings.count) cảnh báo, gen \(generation))"
        )
        return .success(ruleCount: newSnapshot.ruleCount, warningCount: warnings.count)
    }

    // MARK: - Chẩn đoán

    /// Tính lại `DICT_TOKEN_WITHOUT_DICTIONARY` theo trạng thái từ điển **hiện tại** — đây là lỗi
    /// trạng thái runtime, không phải lỗi cú pháp, nên không chốt được lúc compile.
    public func dictionaryIssues() -> [QuickTranslationRuleIssue] {
        guard let snapshot = currentSnapshot else { return [] }
        let tokenConfiguration = QuickTranslationRuleTokenSettings.currentConfiguration()
        var missing: [QuickTranslationRuleElement.DictionaryKind: Bool] = [:]
        var issues: [QuickTranslationRuleIssue] = []

        for rule in snapshot.rules where !rule.requiredDictionaryKinds.isEmpty {
            guard rule.isEnabled(for: tokenConfiguration) else { continue }
            // Rule đang bị tắt ở file tắt chung thì cảnh báo "thiếu từ điển" chỉ là tiếng ồn.
            guard !QuickTranslationRuleDisableStore.shared.isDisabled(pattern: rule.pattern, in: .global) else { continue }
            let unavailable = rule.requiredDictionaryKinds.filter { kind in
                if let cached = missing[kind] { return cached }
                let available = QuickTranslationDictionaryToken.isAvailable(kind)
                missing[kind] = !available
                return !available
            }
            guard unavailable.count == rule.requiredDictionaryKinds.count else { continue }
            issues.append(QuickTranslationRuleIssue(
                sourceLine: rule.sourceLine,
                code: .dictTokenWithoutDictionary,
                message: "Từ điển \(unavailable.map(\.rawValue).joined(separator: "/")) chưa nạp hoặc đang tắt ⇒ rule vô hiệu",
                rawLine: "\(rule.pattern) = \(rule.replacement)"
            ))
            if issues.count >= Self.maxStoredIssues { break }
        }

        return issues
    }

    /// Matcher gọi khi một rule chạm cap backtracking. Ghi log **một lần** cho mỗi dòng.
    public func noteComplexRule(sourceLine: Int) {
        lock.lock()
        let isNew = complexRuleLines.insert(sourceLine).inserted
        let lines = complexRuleLines.sorted()
        lock.unlock()
        guard isNew else { return }
        AppLogger.shared.log("⚠️ [QuickTranslateRule] Rule dòng \(sourceLine) vượt hạn mức backtracking, bị bỏ qua")
        Task { @MainActor in
            self.status.complexRuleLines = lines
        }
    }

    // MARK: - Phụ trợ

    private func makeStatus(from snapshot: QuickTranslationRuleSnapshot) -> Status {
        var status = Status()
        status.isLoaded = true
        status.sourceLabel = snapshot.source.label
        status.hasFile = hasRuleFile
        status.ruleCount = snapshot.ruleCount
        status.warningCount = snapshot.warningCount
        status.sourceHash = snapshot.sourceHash
        status.loadedAt = snapshot.loadedAt
        status.issues = snapshot.issues
        return status
    }

    private func publish(_ status: Status) {
        Task { @MainActor in
            self.status = status
        }
    }

    @MainActor
    private func setDownloading(_ value: Bool) {
        isDownloading = value
    }

    /// Đổi bộ rule = đổi kết quả dịch: dọn cache dịch và phát **đúng một** thông báo cập nhật từ điển.
    private func invalidateTranslationCaches() {
        TranslateUtils.clearCache()
        TranslationManager.shared.notifyDictionariesDidUpdate()
    }
}
