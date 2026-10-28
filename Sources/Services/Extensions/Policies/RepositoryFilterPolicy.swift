import Foundation

public struct RepositoryFilterPolicy: Sendable {
    public static let shared = RepositoryFilterPolicy()

    public init() {}

    /// Khoá `UserDefaults` của công tắc NSFW **toàn app** (Cài đặt › Thư Viện và bộ lọc Kho dùng chung): mặc định
    /// **tắt** và tự tắt lại mỗi lần mở app (`resetNsfwVisibilityOnLaunch`). Tắt ⇒ ẩn tiện ích NSFW ở Kho, Tìm kiếm
    /// mọi nguồn (`SearchExtensionScopePolicy`), Khám phá; ẩn **mọi** sách/tác vụ của nguồn NSFW ở Kệ + Lịch sử
    /// (`ShelfBookPartition`), Tìm trong Kệ, Bộ sưu tập, tab Tải, hub nổi (Tác vụ AI, Video), Quản lý phạm vi dịch,
    /// sheet chọn truyện `BookShareTargetSheet` / `BookImportSourceSheet`; ẩn ô Truy cập nhanh + lịch sử duyệt trang
    /// nguồn NSFW ở Home trình duyệt (`BypassWebView`). Thông báo (chương mới) **không** lọc (người dùng chốt 2026-10-24).
    public static let includeNsfwDefaultsKey = "extFilterIncludeNsfw"

    /// Giá trị hiện tại của công tắc NSFW (khoá chưa ghi ⇒ `false`).
    public static var includesNsfwPreference: Bool {
        UserDefaults.standard.bool(forKey: includeNsfwDefaultsKey)
    }

    /// Gọi đầu `FreeBookApp.init`: mỗi lần mở app công tắc NSFW về tắt (người dùng chốt 2026-10-17).
    public static func resetNsfwVisibilityOnLaunch() {
        UserDefaults.standard.set(false, forKey: includeNsfwDefaultsKey)
    }

    /// Tiện ích `packageId` có phải NSFW không (tra bản cài rồi catalog; không tìm thấy ⇒ `false`).
    public static func isNsfwSource(packageId: String) -> Bool {
        guard let ext = ExtensionLibraryRepository.snapshot(packageId: packageId)
                ?? ExtensionLibraryRepository.catalogSnapshot(packageId: packageId) else { return false }
        return ExtensionNsfwCache.shared.isNsfw(ext)
    }

    /// Bỏ phần tử thuộc nguồn NSFW (sách, tác vụ tải…) khi `includeNsfw == false`, giữ thứ tự; mỗi `packageId` chỉ
    /// tra kho + classifier một lần. Chỉ ẩn hiển thị — dữ liệu giữ nguyên, bật lại là hiện lại.
    public static func excludingNsfwSources<T>(
        _ items: [T],
        includeNsfw: Bool,
        packageId: (T) -> String
    ) -> [T] {
        guard !includeNsfw else { return items }
        var nsfwByPackageId: [String: Bool] = [:]
        return items.filter { item in
            let id = packageId(item)
            if let cached = nsfwByPackageId[id] { return !cached }
            let isNsfw = isNsfwSource(packageId: id)
            nsfwByPackageId[id] = isNsfw
            return !isNsfw
        }
    }

    /// Bỏ tiện ích NSFW (`ExtensionNsfwClassifier`, qua bộ đệm) khi `includeNsfw == false`.
    public static func applyNsfwFilter(_ extensions: [Extension], includeNsfw: Bool) -> [Extension] {
        guard !includeNsfw else { return extensions }
        return extensions.filter { !ExtensionNsfwCache.shared.isNsfw($0) }
    }

    /// Lọc chọn nhiều: **HOẶC** trong một nhóm, **VÀ** giữa các nhóm; nhóm rỗng = không lọc nhóm đó.
    /// `types`/`locales` là **khoá nhóm** (`ExtensionFilterGroups`), so với nhóm của giá trị thô — không so thô.
    /// `includeNsfw == false` ⇒ bỏ tiện ích NSFW; xét **sau cùng** vì classifier đắt hơn các điều kiện khác.
    public func filterExtensions(
        _ extensions: [Extension],
        query: String,
        authors: Set<String> = [],
        types: Set<String> = [],
        locales: Set<String> = [],
        includeNsfw: Bool = true
    ) -> [Extension] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let result = extensions.filter { ext in
            guard authors.isEmpty || authors.contains(ext.author),
                  types.isEmpty || types.contains(ExtensionFilterGroups.typeGroup(for: ext.type)),
                  locales.isEmpty || locales.contains(ExtensionFilterGroups.localeGroup(for: ext.locale)) else { return false }
            if !trimmed.isEmpty {
                let matchesQuery = ext.name.localizedCaseInsensitiveContains(trimmed) ||
                    ext.sourceUrl.localizedCaseInsensitiveContains(trimmed) ||
                    (ext.desc?.localizedCaseInsensitiveContains(trimmed) ?? false)
                guard matchesQuery else { return false }
            }
            return includeNsfw || !ExtensionNsfwCache.shared.isNsfw(ext)
        }
        return sortExtensions(result)
    }

    /// Thứ tự: **tiện ích đã cài có bản cập nhật chưa áp dụng** → đã cài → chưa cài.
    /// Trong nhóm đã cài (kể cả nhóm có cập nhật) theo `ExtensionSortPolicy` (ghim → vừa dùng → A-Z);
    /// nhóm chưa cài (mục catalog từ cache registry) chỉ A-Z.
    /// `hasUpdate` chỉ đúng khi đã cài nên khoá này luôn nằm trong nhóm đã cài.
    public func sortExtensions(_ extensions: [Extension]) -> [Extension] {
        return extensions.sorted { ext1, ext2 in
            if ext1.hasUpdate != ext2.hasUpdate {
                return ext1.hasUpdate
            }
            if ext1.isInstalled != ext2.isInstalled {
                return ext1.isInstalled
            }
            if ext1.isInstalled {
                return ExtensionSortPolicy.areInIncreasingOrder(ext1, ext2)
            }
            return ExtensionSortPolicy.isNameAscending(ext1, ext2)
        }
    }
}
