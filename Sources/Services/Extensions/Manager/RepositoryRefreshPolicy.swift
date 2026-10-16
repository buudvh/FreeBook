import Foundation

/// Nguồn **duy nhất** cho câu hỏi "có được tự làm mới danh sách kho tiện ích lúc này không".
///
/// Vì sao phải có: `RepositoryManagerView.onAppear` gọi `refreshAllRepositories()` mỗi lần tab Tiện
/// Ích hiện ra. Từ khi tiện ích chuyển sang `extension_store/` (JSON), một lượt làm mới chỉ còn
/// **1 request registry cho mỗi kho** (`ExtensionTransactionCoordinator.saveRegistry` lưu nguyên văn
/// registry, danh mục chưa cài dựng từ cache đó) — không còn tải `plugin.json` cho từng tiện ích chưa cài.
/// Cửa này vẫn giữ để không tải lại registry mỗi lần ghé tab. Trước 1.3.330 không có cửa nào cả.
///
/// Refresh **bằng tay** (nút trên toolbar) cố ý **không** đi qua cửa này, giống `checkAllNewChapters`
/// bỏ qua cooldown của `NewChapterCheckPolicy`.
enum RepositoryRefreshPolicy {
    static let cooldownHoursKey = "repositoryRefreshCooldownHours"
    private static let lastRefreshKey = "repositoryLastRefreshAt"

    static let defaultCooldownHours = 6

    static var cooldownHours: Int {
        get {
            let stored = UserDefaults.standard.object(forKey: cooldownHoursKey) as? Int ?? defaultCooldownHours
            return min(max(stored, 1), 48)
        }
        set { UserDefaults.standard.set(min(max(newValue, 1), 48), forKey: cooldownHoursKey) }
    }

    static var lastRefreshAt: Date? {
        get { UserDefaults.standard.object(forKey: lastRefreshKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: lastRefreshKey) }
    }

    /// Lượt **tự động** lúc mở tab. Chưa từng làm mới thì luôn cho chạy.
    static func shouldRunAutoRefresh(now: Date = Date()) -> Bool {
        guard let last = lastRefreshAt else { return true }
        return now.timeIntervalSince(last) >= Double(cooldownHours) * 3600
    }

    /// Chỉ gọi khi lượt làm mới **thật sự** cập nhật được ít nhất một kho: một lượt trắng vì mất mạng
    /// không được khoá cửa 6 tiếng tiếp theo.
    static func markRefreshed(now: Date = Date()) {
        lastRefreshAt = now
    }
}
