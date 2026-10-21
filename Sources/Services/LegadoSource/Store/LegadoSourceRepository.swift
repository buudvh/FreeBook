import Foundation
import Observation

/// Danh sách **tóm tắt** các nguồn Legado đã lưu cho UI (tab "Nguồn Legado") và cho tầng nền.
///
/// - Nguồn sự thật: bản ghi `legado*` trong `ExtensionLibraryRepository` + `source.json` trên đĩa. Repository chỉ
///   là bản chiếu đọc được, nạp **trên nền** (`LegadoSourceStore.fileQueue`) lúc mở app và sau mỗi lần nhập / xoá /
///   khôi phục backup.
/// - Kết quả nạp và kết quả vá file về main bằng `DispatchQueue.main.async` **từ** `fileQueue`, nên được áp đúng thứ
///   tự đã xếp hàng. Bật/tắt vẽ lạc quan ngay; `pendingEnabled` giữ giá trị mới đè lên lượt nạp còn đang bay.
/// - Tên + nhóm dịch QT **một lần** trên nền rồi cache trong `translationMemo` (không dịch trong `body`); dịch lại khi
///   từ điển đổi.
/// - Tầng nền đọc qua `nonisolated static` (`isEnabled(packageId:)`, `summarySnapshot(packageId:)`…). Trước khi nạp
///   xong lần đầu, bảng chụp rỗng ⇒ mọi nguồn coi như tắt.
@MainActor
@Observable
public final class LegadoSourceRepository {
    public static let shared = LegadoSourceRepository()

    /// Sắp theo tên hiển thị (đã gấp hoa thường/dấu).
    public private(set) var summaries: [LegadoSourceSummary] = []
    /// Chip nhóm: nhiều nguồn trước, cùng số thì theo tên dịch.
    public private(set) var groupCounts: [LegadoSourceGroupCount] = []
    public private(set) var ungroupedCount = 0
    public private(set) var isLoading = false
    public private(set) var hasLoaded = false

    @ObservationIgnored private var translationMemo: [String: String] = [:]
    @ObservationIgnored private var pendingEnabled: [String: (value: Bool, token: Int)] = [:]
    @ObservationIgnored private var pendingRemovals: [String: Int] = [:]
    @ObservationIgnored private var nextToken = 0
    @ObservationIgnored private var reloadGeneration = 0
    @ObservationIgnored private var translationTask: Task<Void, Never>?
    @ObservationIgnored private var dictionaryObserver: NSObjectProtocol?

    private init() {
        dictionaryObserver = NotificationCenter.default.addObserver(
            forName: .translationDictionariesDidUpdate,
            object: nil,
            queue: .main
        ) { notification in
            // Chỉ lượt nạp lại từ điển chung; từ điển riêng của một truyện không đổi tên nguồn.
            guard notification.userInfo?["bookId"] == nil else { return }
            MainActor.assumeIsolated { LegadoSourceRepository.shared.retranslateAll() }
        }
    }

    // MARK: - Nạp

    /// Lần đầu sau khi app mở cổng từ điển (`MainTabView`). Gọi nhiều lần vô hại.
    public func loadIfNeeded() {
        guard !hasLoaded, !isLoading else { return }
        reload()
    }

    /// Đọc lại toàn bộ trên `fileQueue` (sau các thao tác file đã xếp hàng trước đó). Lượt cũ hơn bị bỏ khi lượt mới về.
    public func reload() {
        reloadGeneration += 1
        isLoading = true
        Self.enqueueReload(generation: reloadGeneration)
    }

    /// Closure dựng ở ngữ cảnh nonisolated: không bị suy là MainActor-isolated khi chạy trên `fileQueue`.
    nonisolated private static func enqueueReload(generation: Int) {
        LegadoSourceStore.fileQueue.async {
            let started = Date()
            let loaded = Self.readAllSummaries()
            let elapsed = String(format: "%.2f", Date().timeIntervalSince(started))
            AppLogger.shared.log("ℹ️ 📚 [LegadoStore] Nạp \(loaded.count) nguồn Legado trong \(elapsed)s")
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    LegadoSourceRepository.shared.finishReload(loaded, generation: generation)
                }
            }
        }
    }

    nonisolated private static func readAllSummaries() -> [LegadoSourceSummary] {
        let records = ExtensionLibraryRepository.installedSnapshot().filter { LegadoSourceIdentity.isLegado($0) }
        var result: [LegadoSourceSummary] = []
        result.reserveCapacity(records.count)
        var failedNames: [String] = []
        for ext in records {
            do {
                let source = try LegadoSourceStore.loadSource(localPath: ext.localPath)
                result.append(LegadoSourceSummary(packageId: ext.packageId, source: source, version: ext.version))
            } catch {
                failedNames.append(ext.name)
            }
        }
        if !failedNames.isEmpty {
            AppLogger.shared.log("❌ 📚 [LegadoStore] Không đọc được source.json của \(failedNames.count) nguồn: \(failedNames.prefix(10).joined(separator: ", "))")
        }
        return result
    }

    private func finishReload(_ loaded: [LegadoSourceSummary], generation: Int) {
        guard generation == reloadGeneration else { return }
        let currentIds = Set(ExtensionLibraryRepository.shared.installed.lazy
            .filter { LegadoSourceIdentity.isLegado($0) }
            .map(\.packageId))
        var list = loaded.filter { currentIds.contains($0.packageId) && pendingRemovals[$0.packageId] == nil }
        for index in list.indices {
            if let pending = pendingEnabled[list[index].packageId] { list[index].isEnabled = pending.value }
            list[index].applyTranslations(translationMemo)
        }
        isLoading = false
        hasLoaded = true
        publish(list)
        scheduleTranslation()
    }

    // MARK: - Đổi trạng thái (chỉ LegadoSourceCoordinator)

    /// Vẽ lạc quan ngay; trả token để `finishEnabledChange` không xoá giá trị của lần bấm sau.
    func beginEnabledChange(_ packageIds: [String], enabled: Bool) -> Int {
        nextToken += 1
        let token = nextToken
        let ids = Set(packageIds)
        for id in ids { pendingEnabled[id] = (enabled, token) }
        var list = summaries
        for index in list.indices where ids.contains(list[index].packageId) {
            list[index].isEnabled = enabled
        }
        publish(list)
        return token
    }

    /// Vá file xong (gọi trên main theo thứ tự `fileQueue`). Nguồn vá lỗi ⇒ trả về giá trị cũ.
    func finishEnabledChange(_ packageIds: [String], enabled: Bool, token: Int, failed: Set<String>) {
        for id in packageIds where pendingEnabled[id]?.token == token {
            pendingEnabled[id] = nil
        }
        guard !failed.isEmpty else { return }
        var list = summaries
        for index in list.indices where failed.contains(list[index].packageId) && pendingEnabled[list[index].packageId] == nil {
            list[index].isEnabled = !enabled
        }
        publish(list)
    }

    /// Ẩn ngay các nguồn đang xoá (lượt nạp đang bay cũng không đưa chúng trở lại).
    func beginRemoval(_ packageIds: [String]) -> Int {
        nextToken += 1
        let token = nextToken
        let ids = Set(packageIds)
        for id in ids { pendingRemovals[id] = token }
        publish(summaries.filter { !ids.contains($0.packageId) })
        return token
    }

    /// Xoá xong. Nguồn xoá thất bại hiện lại ở lượt nạp kế tiếp.
    func finishRemoval(_ packageIds: [String], token: Int) {
        for id in packageIds where pendingRemovals[id] == token {
            pendingRemovals[id] = nil
            pendingEnabled[id] = nil
        }
    }

    // MARK: - Dịch

    private func retranslateAll() {
        translationMemo = [:]
        guard hasLoaded else { return }
        scheduleTranslation()
    }

    /// Dịch các tên/nhóm chưa có trong memo trên nền, rồi gắn vào danh sách hiện tại (không đụng bật/tắt).
    private func scheduleTranslation() {
        var pending = Set<String>()
        for summary in summaries {
            if translationMemo[summary.name] == nil { pending.insert(summary.name) }
            for group in summary.groups where translationMemo[group] == nil { pending.insert(group) }
        }
        guard !pending.isEmpty else { return }
        translationTask?.cancel()
        let texts = Array(pending)
        translationTask = Task.detached(priority: .utility) {
            let started = Date()
            guard let memo = LegadoSourceTranslator.translate(texts), !Task.isCancelled else { return }
            let elapsed = String(format: "%.2f", Date().timeIntervalSince(started))
            AppLogger.shared.log("ℹ️ 📚 [LegadoStore] Dịch QT \(memo.count) tên/nhóm nguồn trong \(elapsed)s")
            await MainActor.run {
                LegadoSourceRepository.shared.mergeTranslations(memo)
            }
        }
    }

    private func mergeTranslations(_ memo: [String: String]) {
        translationMemo.merge(memo) { _, new in new }
        var list = summaries
        for index in list.indices { list[index].applyTranslations(translationMemo) }
        publish(list)
    }

    // MARK: - Publish

    private func publish(_ list: [LegadoSourceSummary]) {
        let sorted = list.sorted { lhs, rhs in
            lhs.sortKey == rhs.sortKey ? lhs.packageId < rhs.packageId : lhs.sortKey < rhs.sortKey
        }
        var counts: [String: (translated: String, count: Int)] = [:]
        var ungrouped = 0
        for summary in sorted {
            if summary.groups.isEmpty { ungrouped += 1 }
            for (index, group) in summary.groups.enumerated() {
                let translated = index < summary.translatedGroups.count ? summary.translatedGroups[index] : group
                counts[group] = (translated, (counts[group]?.count ?? 0) + 1)
            }
        }
        groupCounts = counts
            .map { LegadoSourceGroupCount(group: $0.key, translatedGroup: $0.value.translated, count: $0.value.count) }
            .sorted { lhs, rhs in
                lhs.count == rhs.count
                    ? LegadoSourceSummary.fold(lhs.translatedGroup) < LegadoSourceSummary.fold(rhs.translatedGroup)
                    : lhs.count > rhs.count
            }
        ungroupedCount = ungrouped
        summaries = sorted
        LegadoSourceSnapshotTable.shared.replace(sorted, isReady: hasLoaded)
    }

    // MARK: - Tra cứu từ tầng nền (không cần await)

    /// Nguồn đang bật. Chưa nạp xong / không có ⇒ `false`.
    nonisolated public static func isEnabled(packageId: String) -> Bool {
        LegadoSourceSnapshotTable.shared.summary(packageId: packageId)?.isEnabled ?? false
    }

    nonisolated public static func summarySnapshot(packageId: String) -> LegadoSourceSummary? {
        LegadoSourceSnapshotTable.shared.summary(packageId: packageId)
    }

    nonisolated public static func allSummariesSnapshot() -> [LegadoSourceSummary] {
        LegadoSourceSnapshotTable.shared.all()
    }

    /// `true` sau lần nạp đầu tiên — trước đó `isEnabled` luôn `false`.
    nonisolated public static var isSnapshotReady: Bool {
        LegadoSourceSnapshotTable.shared.isReady
    }
}
