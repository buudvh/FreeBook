import Foundation

/// Danh tính tiện ích trong danh mục kho (1.3.753): **tên + tác giả**. Hai mục cùng tên khác tác giả là hai tiện ích
/// khác nhau — hiện hai hàng và cài song song được (thư mục, cấu hình, `localStorage` riêng). Cùng tên cùng tác giả
/// (so không phân biệt hoa thường) là một tiện ích: kho đứng trước thắng như cũ.
///
/// Mã (`packageId`) vẫn bắt đầu từ `ExtensionSyncCommandBuilder.packageId(forName:)`. Chỉ khi mã đó đã bị một tiện ích
/// khác giữ (bản đã cài, hoặc mục của kho đứng trước) thì mục sau nhận `<mã>__<tác giả>`. Tiện ích đã cài giữ nguyên
/// mã đã lưu, nên truyện trên kệ / TTS / cấu hình không đổi. Import zip và Debug vẫn chỉ theo tên (`rules.md`).
enum ExtensionCatalogIdentity {
    /// Một dòng registry kèm mã theo tên và khoá danh tính, tính sẵn một lần mỗi khi cache kho đổi.
    struct Entry: Sendable {
        let item: ExtensionRegistryItem
        let base: String
        let key: String
    }

    /// Chỉ mục của cache registry một kho: giữ thứ tự gốc để dựng danh mục + tra nhanh (mục đứng trước thắng).
    struct RegistryIndex: Sendable {
        let entries: [Entry]
        private let byKey: [String: ExtensionRegistryItem]
        private let byBase: [String: ExtensionRegistryItem]

        init(items: [ExtensionRegistryItem]) {
            var entries: [Entry] = []
            var byKey: [String: ExtensionRegistryItem] = [:]
            var byBase: [String: ExtensionRegistryItem] = [:]
            entries.reserveCapacity(items.count)
            for item in items {
                let base = ExtensionSyncCommandBuilder.packageId(forName: item.name)
                let key = ExtensionCatalogIdentity.key(base: base, author: item.author)
                entries.append(Entry(item: item, base: base, key: key))
                if byKey[key] == nil { byKey[key] = item }
                if byBase[base] == nil { byBase[base] = item }
            }
            self.entries = entries
            self.byKey = byKey
            self.byBase = byBase
        }

        /// Mục của một tiện ích trong kho của nó: tên + tác giả → mã đã lưu (cách ghép trước 1.3.753) → tên. Bậc sau
        /// đỡ cho tiện ích đã cài có tác giả trong `plugin.json` khác chữ với registry.
        func item(packageId: String, name: String, author: String?) -> ExtensionRegistryItem? {
            let base = ExtensionSyncCommandBuilder.packageId(forName: name)
            return byKey[ExtensionCatalogIdentity.key(base: base, author: author)]
                ?? byBase[packageId]
                ?? byBase[base]
        }
    }

    static func key(name: String, author: String?) -> String {
        key(base: ExtensionSyncCommandBuilder.packageId(forName: name), author: author)
    }

    static func key(base: String, author: String?) -> String {
        base + "\u{1F}" + normalizedAuthor(author)
    }

    /// Mã cho một mục chưa cài: mã theo tên khi còn trống, không thì `<mã>__<tác giả>`; cả hai đã bị giữ ⇒ `nil` (bỏ mục).
    static func packageId(base: String, author: String?, taken: Set<String>) -> String? {
        guard !base.isEmpty else { return nil }
        if !taken.contains(base) { return base }
        let suffixed = base + "__" + authorSlug(author)
        return taken.contains(suffixed) ? nil : suffixed
    }

    /// Tác giả thành một đoạn tên thư mục: chữ thường, khoảng trắng ⇒ `_`, ký tự đường dẫn ⇒ `_`; rỗng ⇒ `an_danh`.
    static func authorSlug(_ author: String?) -> String {
        let slug = normalizedAuthor(author)
            .components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: "_")
            .components(separatedBy: CharacterSet(charactersIn: "/\\:")).joined(separator: "_")
        return slug.isEmpty ? "an_danh" : slug
    }

    private static func normalizedAuthor(_ author: String?) -> String {
        (author ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
