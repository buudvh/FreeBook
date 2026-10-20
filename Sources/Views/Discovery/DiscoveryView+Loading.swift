import Foundation

/// Phần tải danh mục của `DiscoveryView`, tách khỏi file gốc để giữ dưới baseline dòng. Chỉ gồm hàm tĩnh không đụng
/// state — `loadDiscoveryData` (file gốc) giữ việc huỷ lượt cũ và chặn ghi đè khi nguồn đã đổi.
extension DiscoveryView {
    /// Tải song song `home` và `genre` của một nguồn. Có `exploreTab` ⇒ tab đó đứng đầu, các tab `home` vẫn xếp sau.
    /// Cố ý khác hợp đồng extension (khai cả hai thì `explore` thắng, `home` bị bỏ) — người dùng chọn giữ cả hai
    /// (1.3.554). Thiếu script hoặc lỗi ⇒ mảng rỗng cho phần đó; phần còn lại vẫn dùng được.
    static func fetchCatalog(_ ext: Extension, exploreTab: CategoryResult?) async -> (home: [CategoryResult], genre: [CategoryResult]) {
        let localPath = ext.localPath
        let downloadUrl = ext.downloadUrl
        let configJson = ext.configJson
        async let genre = fetchGenre(localPath: localPath, downloadUrl: downloadUrl, configJson: configJson)
        let home = await fetchHome(localPath: localPath, downloadUrl: downloadUrl, configJson: configJson)
        // Dùng lại đúng `exploreTab` được truyền vào: tạo tab mới sẽ đổi id và trang section bị dựng/tải lại.
        return ((exploreTab.map { [$0] } ?? []) + home, await genre)
    }

    /// Tab được chọn sau một lượt tải: tab đang xem nếu còn tồn tại → tab đã nhớ (`saved`) → tab `home` đầu tiên →
    /// tab Thể loại. Không có dữ liệu ⇒ `""`.
    static func resolveCategoryId(
        current: String,
        saved: String,
        home: [CategoryResult],
        hasGenre: Bool,
        genresTabId: String
    ) -> String {
        func isAvailable(_ id: String) -> Bool {
            guard !id.isEmpty else { return false }
            return id == genresTabId ? hasGenre : home.contains { $0.id == id }
        }
        if isAvailable(current) { return current }
        if isAvailable(saved) { return saved }
        if let first = home.first { return first.id }
        return hasGenre ? genresTabId : ""
    }

    private static func fetchHome(localPath: String, downloadUrl: String, configJson: String) async -> [CategoryResult] {
        do {
            return try await ExtensionManager.shared.home(localPath: localPath, downloadUrl: downloadUrl, configJson: configJson)
        } catch {
            #if DEBUG
            AppLogger.shared.log("⚠️ [DiscoveryView] Không có hoặc lỗi chạy script home: \(error.localizedDescription)")
            #endif
            return []
        }
    }

    private static func fetchGenre(localPath: String, downloadUrl: String, configJson: String) async -> [CategoryResult] {
        do {
            return try await ExtensionManager.shared.genre(localPath: localPath, downloadUrl: downloadUrl, configJson: configJson)
        } catch {
            #if DEBUG
            AppLogger.shared.log("⚠️ [DiscoveryView] Không có hoặc lỗi chạy script genre: \(error.localizedDescription)")
            #endif
            return []
        }
    }
}
