import Foundation
import Observation
import os
import WebKit

/// Bản chụp rule list cho `AdBlockRuleListProvider.currentRuleLists()` — đọc đồng bộ từ thread bất kỳ.
///
/// `WKContentRuleList` là class ObjC không `Sendable` nên dùng `init(uncheckedState:)`: an toàn vì rule list
/// **bất biến** sau khi biên dịch, WebKit cho dùng chung giữa các webview, và chỉ được gắn vào webview trên main
/// thread (`WebContentConfigurator`). Chỉ MainActor (provider) ghi; lock chỉ giữ trong lúc chép mảng.
private let adBlockRuleListSnapshot = OSAllocatedUnfairLock(uncheckedState: [WKContentRuleList]())

/// Bộ cache + trạng thái chặn quảng cáo: nạp/biên dịch rule list của các bộ lọc **đang bật**, tự cập nhật bộ quá
/// hạn, phục vụ màn Cài đặt (`statuses`, `isUpdating`, `progressText`) và webview (`currentRuleLists()`).
///
/// Mọi việc nặng (nạp, tải, biên dịch) chạy **tuần tự** qua một chuỗi task — hai lượt biên dịch cùng
/// `adblock-<id>` không bao giờ chồng nhau. Việc CPU (chuyển đổi) chạy nền `.utility`; API WebKit chạy trên main.
///
/// Webview tạo trước khi bộ lọc sẵn sàng nhận `[]` (không chờ) — chỉ còn cổng 11 tên miền cũ ở lượt nạp đó.
@MainActor
@Observable
final class AdBlockRuleListProvider {
    static let shared = AdBlockRuleListProvider()

    private(set) var statuses: [Int: AdBlockFilterStatus] = [:]
    private(set) var isUpdating = false
    /// "Đang cập nhật 2/4…" khi đang tải; `nil` khi rảnh.
    private(set) var progressText: String?

    /// Số bộ đang bật đã có rule list (chữ phụ "Đã chặn quảng cáo bằng N bộ lọc").
    var readyFilterCount: Int {
        enabledFilterIds.filter { ruleLists[$0] != nil }.count
    }

    /// Bản sao của `WebContentSettings.enabledFilterIds` để Observation vẽ lại công tắc từng bộ.
    private var enabledFilterIds: Set<Int> = []
    /// Rule list đã nạp trong phiên này (cả bộ vừa tắt — bật lại thì dùng ngay).
    private var ruleLists: [Int: WKContentRuleList] = [:]

    @ObservationIgnored private var didWarmUp = false
    @ObservationIgnored private var isUpdateQueued = false
    @ObservationIgnored private var workTail: Task<Void, Never>?

    private var worker: AdBlockUpdateWorker { AdBlockUpdateWorker.shared }

    private init() {
        enabledFilterIds = WebContentSettings.enabledFilterIds
        var initial: [Int: AdBlockFilterStatus] = [:]
        for filter in AdBlockFilter.catalog { initial[filter.id] = .empty }
        statuses = initial
    }

    // MARK: - API cho webview

    /// Rule list của các bộ **đang bật** đã sẵn sàng, theo thứ tự danh mục. Đồng bộ, không chờ; `[]` khi chưa có.
    /// Có bật chặn quảng cáo cho webview hay không là việc của `WebContentPolicy` — hàm này không xét.
    nonisolated static func currentRuleLists() -> [WKContentRuleList] {
        adBlockRuleListSnapshot.withLockUnchecked { $0 }
    }

    // MARK: - API cho UI / khởi động

    /// Gọi từ `MainTabView` (`.task(priority: .utility)`). Gọi nhiều lần chỉ chạy một lần: nạp/biên dịch các bộ
    /// đang bật từ file đã tải hoặc bản đóng gói, rồi tải các bộ quá hạn ở nền.
    func warmUp() {
        guard !didWarmUp else { return }
        didWarmUp = true
        enqueue { await self.loadEnabledFilters() }
        enqueue { await self.updateIfNeeded(force: false) }
    }

    /// Nút "Cập nhật ngay": tải lại mọi bộ đang bật bất kể hạn dùng. Đang cập nhật / đã xếp hàng ⇒ bỏ qua.
    func updateNow() {
        guard !isUpdating, !isUpdateQueued else { return }
        isUpdateQueued = true
        enqueue {
            self.isUpdateQueued = false
            await self.updateIfNeeded(force: true)
        }
    }

    /// Bật ⇒ nạp từ file/bản đóng gói (chưa có thì tải) rồi biên dịch; tắt ⇒ bỏ khỏi bản chụp ngay (không xoá file).
    /// Đổi có hiệu lực từ lượt nạp trang kế tiếp của mỗi webview.
    func setFilter(id: Int, enabled: Bool) {
        guard let filter = AdBlockFilter.filter(id: id) else { return }
        var ids = enabledFilterIds
        if enabled { ids.insert(id) } else { ids.remove(id) }
        guard ids != enabledFilterIds else { return }
        enabledFilterIds = ids
        WebContentSettings.setEnabledFilterIds(ids)
        publishSnapshot()
        refreshHasData(for: id)
        guard enabled else { return }
        enqueue { await self.prepareEnabledFilter(filter) }
    }

    func isFilterEnabled(_ id: Int) -> Bool {
        enabledFilterIds.contains(id)
    }

    // MARK: - Chuỗi việc tuần tự

    private func enqueue(_ job: @escaping @MainActor @Sendable () async -> Void) {
        let previous = workTail
        workTail = Task(priority: .utility) { @MainActor in
            await previous?.value
            await job()
        }
    }

    // MARK: - Nạp / biên dịch

    private func loadEnabledFilters() async {
        await refreshAllStatuses()
        for filter in AdBlockFilter.catalog where enabledFilterIds.contains(filter.id) && ruleLists[filter.id] == nil {
            await loadFilter(filter)
        }
        AppLogger.shared.log("🛡️ [AdBlock] Sẵn sàng \(readyFilterCount)/\(enabledFilterIds.count) bộ lọc đang bật")
    }

    /// Bộ vừa bật: có nguồn thì nạp; chưa có nguồn hoặc nguồn quá hạn thì tải (rồi nạp lại nếu nội dung mới).
    private func prepareEnabledFilter(_ filter: AdBlockFilter) async {
        let id = filter.id
        guard enabledFilterIds.contains(id) else { return }
        if ruleLists[id] == nil, await worker.hasSource(for: filter) {
            await loadFilter(filter)
        }
        guard enabledFilterIds.contains(id),
              !(await worker.filtersDue([id], force: false)).isEmpty else { return }
        await downloadAndReload(filter)
    }

    /// Nạp rule list một bộ từ nguồn hiện có (file tải, không có thì bản đóng gói):
    /// - nguồn + `compilerKey` trùng lần biên dịch trước và WebKit còn giữ ⇒ chỉ `lookUp` (không chuyển đổi);
    /// - khác ⇒ chuyển đổi; JSON trùng lần trước và WebKit còn giữ ⇒ `lookUp`, không thì biên dịch.
    /// Lỗi ⇒ giữ rule list cũ (nếu có) + log `❌`. Trả `true` khi có rule list mới.
    @discardableResult
    private func loadFilter(_ filter: AdBlockFilter) async -> Bool {
        let id = filter.id
        guard let source = await worker.source(for: filter) else {
            refreshHasData(for: id)
            return false
        }
        let previous = await worker.meta(id: id)
        let compilerKey = AdBlockRuleCompiler.compilerKey
        let sameCompiler = previous?.compilerKey == compilerKey
        if sameCompiler, previous?.compiledSourceChecksum == source.checksum,
           let cached = await AdBlockRuleCompiler.lookUp(filterId: id) {
            install(cached, for: id, ruleCount: previous?.safariRuleCount, updatedAt: source.updatedAt)
            return true
        }

        let startedAt = Date()
        let conversion = await AdBlockRuleCompiler.convert(source.text)
        let origin = source.isBundled ? "bản đóng gói" : "bản đã tải"
        AppLogger.shared.log(
            "🛡️ [AdBlock] Chuyển đổi bộ \(id) (\(origin)): \(conversion.safariRuleCount) luật WebKit / "
                + "\(conversion.sourceRuleCount) luật nguồn, \(conversion.errorsCount) luật không chuyển được, "
                + "\(Int(Date().timeIntervalSince(startedAt) * 1000)) ms"
        )
        if conversion.discardedRuleCount > 0 {
            AppLogger.shared.log("❌ 🛡️ [AdBlock] Bộ \(id) vượt trần WebKit: bỏ \(conversion.discardedRuleCount) luật")
        }
        guard conversion.safariRuleCount > 0 else {
            AppLogger.shared.log("❌ 🛡️ [AdBlock] Bộ \(id) chuyển đổi ra 0 luật — bỏ qua")
            refreshHasData(for: id)
            return false
        }

        let list: WKContentRuleList
        if sameCompiler, previous?.compiledJSONChecksum == conversion.jsonChecksum,
           let cached = await AdBlockRuleCompiler.lookUp(filterId: id) {
            list = cached
        } else {
            do {
                list = try await AdBlockRuleCompiler.compile(filterId: id, json: conversion.json)
            } catch {
                AppLogger.shared.log("❌ 🛡️ [AdBlock] Biên dịch bộ \(id) thất bại: \(error.localizedDescription)")
                refreshHasData(for: id)
                return false
            }
        }
        await worker.recordCompiled(
            id: id,
            sourceChecksum: source.checksum,
            jsonChecksum: conversion.jsonChecksum,
            compilerKey: compilerKey,
            sourceRuleCount: conversion.sourceRuleCount,
            safariRuleCount: conversion.safariRuleCount
        )
        install(list, for: id, ruleCount: conversion.safariRuleCount, updatedAt: source.updatedAt)
        return true
    }

    private func install(_ list: WKContentRuleList, for id: Int, ruleCount: Int?, updatedAt: Date?) {
        ruleLists[id] = list
        var status = statuses[id] ?? .empty
        status.hasData = true
        if let ruleCount { status.safariRuleCount = ruleCount }
        if let updatedAt { status.updatedAt = updatedAt }
        if status != statuses[id] { statuses[id] = status }
        // Bộ bị tắt trong lúc đang biên dịch không lọt vào bản chụp: `publishSnapshot` lọc theo bộ đang bật.
        publishSnapshot()
    }

    /// Ghi bản chụp cho `currentRuleLists()` — chỉ gọi từ MainActor.
    private func publishSnapshot() {
        let lists = AdBlockFilter.catalog.compactMap { filter in
            enabledFilterIds.contains(filter.id) ? ruleLists[filter.id] : nil
        }
        adBlockRuleListSnapshot.withLockUnchecked { $0 = lists }
    }

    // MARK: - Cập nhật

    /// Tải các bộ đang bật đã quá hạn (`force` ⇒ tất cả), nội dung mới thì biên dịch lại.
    private func updateIfNeeded(force: Bool) async {
        let ids = AdBlockFilter.catalog.map(\.id).filter { enabledFilterIds.contains($0) }
        let due = await worker.filtersDue(ids, force: force)
        guard !due.isEmpty else { return }
        isUpdating = true
        AppLogger.shared.log("🛡️ [AdBlock] Cập nhật \(due.count) bộ lọc\(force ? " (bấm Cập nhật ngay)" : "")")
        for (index, id) in due.enumerated() {
            guard let filter = AdBlockFilter.filter(id: id), enabledFilterIds.contains(id) else { continue }
            progressText = "Đang cập nhật \(index + 1)/\(due.count)…"
            await downloadAndReload(filter)
        }
        progressText = nil
        isUpdating = false
    }

    private func downloadAndReload(_ filter: AdBlockFilter) async {
        let id = filter.id
        setUpdating(true, for: id)
        switch await worker.download(filter) {
        case .updated:
            await loadFilter(filter)
        case .unchanged:
            if ruleLists[id] == nil { await loadFilter(filter) }
        case .failed:
            break
        }
        await refreshStatus(for: filter)
        setUpdating(false, for: id)
    }

    // MARK: - Trạng thái

    private func setUpdating(_ updating: Bool, for id: Int) {
        var status = statuses[id] ?? .empty
        guard status.isUpdating != updating else { return }
        status.isUpdating = updating
        statuses[id] = status
    }

    private func refreshAllStatuses() async {
        for filter in AdBlockFilter.catalog {
            await refreshStatus(for: filter)
        }
    }

    /// Ngày/số luật/lỗi lấy từ meta của worker; `hasData` theo rule list thật (bộ đang tắt: theo meta).
    private func refreshStatus(for filter: AdBlockFilter) async {
        let seed = await worker.statusSeed(for: filter)
        let id = filter.id
        var status = statuses[id] ?? .empty
        status.updatedAt = seed.updatedAt
        status.lastError = seed.lastError
        if let count = seed.safariRuleCount { status.safariRuleCount = count }
        status.hasData = ruleLists[id] != nil || (!enabledFilterIds.contains(id) && seed.hasCompiledData)
        if status != statuses[id] { statuses[id] = status }
    }

    private func refreshHasData(for id: Int) {
        guard var status = statuses[id] else { return }
        let hasData = ruleLists[id] != nil || (!enabledFilterIds.contains(id) && status.safariRuleCount != nil)
        guard status.hasData != hasData else { return }
        status.hasData = hasData
        statuses[id] = status
    }
}
