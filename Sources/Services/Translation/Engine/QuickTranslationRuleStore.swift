import Foundation
import Combine

/// Chủ sở hữu duy nhất của bộ rule dịch: tải/nhập file, validate-then-swap **atomically**, giữ
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
        /// Có hard error ⇒ **không** ghi file, **không** swap snapshot; bộ đang chạy giữ nguyên.
        case rejected(issues: [QuickTranslationRuleIssue])
        case failure(message: String)
    }

    @MainActor @Published public private(set) var status = Status()
    @MainActor @Published public private(set) var isDownloading = false

    private let lock = NSLock()
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

    /// Thẻ đi vào cache key dịch: trạng thái công tắc + generation của snapshot.
    public var cacheTag: String {
        lock.lock()
        let generation = generationCounter
        lock.unlock()
        return "\(isEnabled ? 1 : 0):\(generation)"
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
        guard let text = try? String(contentsOf: ruleFileURL, encoding: .utf8) else {
            publish(Status())
            return .failure(message: "Chưa có bộ rule nào trên máy")
        }
        return apply(text: text, source: .local, notifiesObservers: notifiesObservers)
    }

    /// Nhập/ghi bộ rule: parse + validate + compile **toàn bộ vào staging**, chỉ khi không có hard
    /// error mới ghi file và swap snapshot. Có hard error thì file cũ giữ nguyên.
    ///
    /// `mode` mặc định `.replaceAll` để hai caller không có UI chọn chế độ — nút tải bộ mặc định và
    /// khôi phục backup — giữ đúng hành vi cũ. Trộn xong thì validate **toàn bộ** kết quả, không chỉ
    /// phần mới: một rule cũ vẫn có thể thành lỗi khi đứng cạnh rule mới (trùng mẫu, capture không dùng).
    ///
    /// `notifiesObservers: false` dành riêng cho **khôi phục backup**: `BackupRestoreWorker` tự phát
    /// `notifyDictionariesDidUpdate()` một lần ở cuối lượt, nên nếu ở đây phát thêm thì Reader dựng
    /// lại hai lượt và lượt đầu còn đang dở dữ liệu. Bất biến "một lần đổi bộ rule = **một** thông
    /// báo" là của plan §11.
    public func importRules(
        text: String,
        source: QuickTranslationRuleSnapshot.Source = .imported,
        mode: DataImportMode = .replaceAll,
        notifiesObservers: Bool = true
    ) -> LoadOutcome {
        let merged: String
        if mode == .replaceAll {
            merged = text
        } else {
            merged = QuickTranslationRuleFileEditor.merge(
                current: currentSourceText() ?? "",
                imported: text,
                mode: mode
            )
        }

        guard merged.utf8.count <= Self.maxRuleFileBytes else {
            return .failure(message: "File rule vượt 8 MB, gần như chắc chắn không phải bộ rule")
        }

        let staged = QuickTranslationRuleCompiler.compile(QuickTranslationRuleParser.parse(merged))
        if staged.hasHardError {
            return .rejected(issues: staged.issues.filter { $0.severity == .hard })
        }

        do {
            try Data(merged.utf8).write(to: ruleFileURL, options: .atomic)
        } catch {
            return .failure(message: "Không ghi được file rule: \(error.localizedDescription)")
        }
        return apply(
            text: merged,
            source: source,
            precompiled: staged,
            notifiesObservers: notifiesObservers
        )
    }

    /// Tải bộ rule mặc định từ HuggingFace rồi đi tiếp bằng đúng đường `importRules` — tức vẫn
    /// validate-then-swap, file cũ chỉ bị thay khi bản mới sạch hard error.
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

    private func apply(
        text: String,
        source: QuickTranslationRuleSnapshot.Source,
        precompiled: QuickTranslationRuleCompiler.Result? = nil,
        notifiesObservers: Bool = true
    ) -> LoadOutcome {
        let compiled = precompiled ?? QuickTranslationRuleCompiler.compile(QuickTranslationRuleParser.parse(text))
        if compiled.hasHardError {
            return .rejected(issues: compiled.issues.filter { $0.severity == .hard })
        }

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
        var missing: [QuickTranslationRuleElement.DictionaryKind: Bool] = [:]
        var issues: [QuickTranslationRuleIssue] = []

        for rule in snapshot.rules where !rule.requiredDictionaryKinds.isEmpty {
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

    /// Đổi bộ rule = đổi kết quả dịch: dọn cache dịch và phát **đúng một** thông báo cập nhật từ điển
    /// để Reader/TTS dựng lại snapshot. Không tạo đường refresh thứ hai.
    ///
    /// Chỉ hai lời gọi, không nhiều hơn: `clearCache()` là thứ duy nhất xoá được `NSCache` bản dịch
    /// (và nó đã tự `chapterTitleCacheDict.removeAll()` nên **không** gọi thêm
    /// `clearChapterTitleCache()`), còn `notifyDictionariesDidUpdate()` mới là kênh để Reader/TTS
    /// dựng lại. Lời gọi thứ hai bên trong nó có tự bump generation lần nữa
    /// (`TranslateUtils.invalidateCache`) — vô hại vì điều kiện là generation **đổi**, không phải
    /// đổi đúng một lần.
    private func invalidateTranslationCaches() {
        TranslateUtils.clearCache()
        TranslationManager.shared.notifyDictionariesDidUpdate()
    }
}
