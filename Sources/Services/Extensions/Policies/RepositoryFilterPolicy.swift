import Foundation

public struct RepositoryFilterPolicy: Sendable {
    public static let shared = RepositoryFilterPolicy()

    public init() {}

    public func filterExtensions(
        _ extensions: [Extension],
        query: String,
        author: String = "all",
        type: String = "all",
        locale: String = "all"
    ) -> [Extension] {
        var result = extensions.filter { $0.type != ExtensionType.comic }
        if author != "all" {
            result = result.filter { $0.author == author }
        }
        if type != "all" {
            result = result.filter { $0.type == type }
        }
        if locale != "all" {
            result = result.filter { $0.locale == locale }
        }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            result = result.filter {
                $0.name.localizedCaseInsensitiveContains(trimmed) ||
                $0.sourceUrl.localizedCaseInsensitiveContains(trimmed) ||
                ($0.desc?.localizedCaseInsensitiveContains(trimmed) ?? false)
            }
        }
        return sortExtensions(result)
    }

    public func sortExtensions(_ extensions: [Extension]) -> [Extension] {
        return extensions.sorted { ext1, ext2 in
            let isInstalled1 = !ext1.localPath.isEmpty
            let isInstalled2 = !ext2.localPath.isEmpty
            if isInstalled1 != isInstalled2 {
                return isInstalled1 && !isInstalled2
            }
            if ext1.isPinned != ext2.isPinned {
                return ext1.isPinned && !ext2.isPinned
            }
            return ext1.name.localizedCompare(ext2.name) == .orderedAscending
        }
    }
}
