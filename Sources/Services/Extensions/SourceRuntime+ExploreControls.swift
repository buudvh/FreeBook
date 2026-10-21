import Foundation

/// Khám phá động của nguồn Legado (spec §11) cho màn Khám phá, tra nguồn theo `localPath` như mọi hàm khác của
/// facade. Tiện ích JS không có khám phá động: các hàm trả `[]` / `nil` / không làm gì.
///
/// Mọi hàm chạy engine đều `async` (chạy ngoài main) và chạy trong ngữ cảnh **có người dùng** — chúng chỉ được gọi khi
/// người dùng đang xem tab Khám phá của nguồn, nên `java.startBrowserAwait` (vd vượt Cloudflare) được trình bày.
///
/// Vòng điều khiển: đổi `select`/`toggle`/`text` ⇒ `setLegadoExploreValue` (ghi `infoMap` bền ngay) ⇒ có `action` thì
/// `runLegadoExploreAction` ⇒ JS thường gọi `java.refreshExplore()` ⇒ presenter ở root phát tín hiệu làm mới ⇒ màn
/// điều khiển gọi lại `legadoExploreItems(preferCached: false)`. Ô bấm mở danh sách như cũ (`executeCustomScript`
/// với `legadoExploreScriptName`).
extension SourceRuntime {
    /// Danh mục khám phá của nguồn Legado cho `DiscoveryView` (thay `genre` ở nhánh Legado): chạy `exploreUrl` **một lần**
    /// (có người dùng), ghi đệm mục có kiểu cho tab điều khiển, trả các ô bấm đúng như `genre`. Nguồn chỉ có điều khiển
    /// (chưa sinh ô bấm nào) vẫn trả **một mục giữ chỗ** để tab lưới hiện ra — tab của nguồn Legado tự vẽ từ mục có kiểu,
    /// không dùng danh sách này.
    func legadoExploreCatalog(localPath: String) async throws -> [CategoryResult] {
        guard let target = try legadoTarget(localPath) else { return [] }
        let items = try await legadoCall("exploreEntries", "exploreUrl", interactive: true) {
            try await LegadoSourceRuntime.exploreEntries(target)
        }
        let categories = LegadoSourceRuntime.exploreCategories(from: items, scriptName: Self.legadoExploreScriptName)
        if categories.isEmpty, items.contains(where: { $0.isControl }) {
            return [CategoryResult(title: "Khám phá", input: "", script: "")]
        }
        return categories
    }

    /// Mọi mục khám phá có kiểu (tiêu đề nhóm, ô bấm, điều khiển kèm giá trị hiện tại). `preferCached`: dùng kết quả
    /// vừa chạy ở `legadoExploreCatalog` nếu còn hạn (mở tab lần đầu); `false` khi làm mới / `java.refreshExplore`.
    func legadoExploreItems(localPath: String, preferCached: Bool) async throws -> [LegadoEngineExploreItem] {
        guard let target = try legadoTarget(localPath) else { return [] }
        if preferCached, let cached = LegadoSourceRuntime.exploreEntriesCache.items(key: LegadoSourceRuntime.exploreCacheKey(target)) {
            return cached
        }
        return try await legadoCall("exploreEntries", "exploreUrl", interactive: true) {
            try await LegadoSourceRuntime.exploreEntries(target)
        }
    }

    /// Ghi giá trị người dùng chọn/nhập cho điều khiển `title` vào `infoMap` của nguồn (bền ngay); `nil` ⇒ xoá.
    /// `async` để việc ghi tệp trạng thái chạy ngoài main.
    func setLegadoExploreValue(_ value: String?, forTitle title: String, localPath: String) async throws {
        guard let target = try legadoTarget(localPath) else { return }
        LegadoExploreService.setValue(value, forTitle: title, source: target.engineSource)
        LegadoSourceRuntime.exploreEntriesCache.updateValue(value, forTitle: title,
                                                            key: LegadoSourceRuntime.exploreCacheKey(target))
    }

    /// Chạy `action` của điều khiển (spec §11.4). Trả thông báo lỗi JS (UI hiện "Lỗi: …"), `nil` khi chạy xong.
    /// Không log mã `action`.
    func runLegadoExploreAction(_ action: String, localPath: String) async throws -> String? {
        guard let target = try legadoTarget(localPath) else { return nil }
        return try await legadoCall("exploreAction", "\(action.utf16.count) ký tự", interactive: true) {
            try await LegadoExploreService.runAction(action, source: target.engineSource)
        }
    }
}
