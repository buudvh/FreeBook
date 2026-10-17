import Foundation

public struct RepositoryFilterPolicy: Sendable {
    public static let shared = RepositoryFilterPolicy()

    public init() {}

    /// Lọc chọn nhiều: **HOẶC** trong một nhóm, **VÀ** giữa các nhóm; nhóm rỗng = không lọc nhóm đó.
    /// `types`/`locales` là **khoá nhóm** (`ExtensionFilterGroups`), so với nhóm của giá trị thô — không so thô.
    public func filterExtensions(
        _ extensions: [Extension],
        query: String,
        authors: Set<String> = [],
        types: Set<String> = [],
        locales: Set<String> = []
    ) -> [Extension] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let result = extensions.filter { ext in
            guard authors.isEmpty || authors.contains(ext.author),
                  types.isEmpty || types.contains(ExtensionFilterGroups.typeGroup(for: ext.type)),
                  locales.isEmpty || locales.contains(ExtensionFilterGroups.localeGroup(for: ext.locale)) else { return false }
            guard !trimmed.isEmpty else { return true }
            return ext.name.localizedCaseInsensitiveContains(trimmed) ||
                ext.sourceUrl.localizedCaseInsensitiveContains(trimmed) ||
                (ext.desc?.localizedCaseInsensitiveContains(trimmed) ?? false)
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
