import Foundation

/// Chuyển **một lần** tiện ích/kho từ bảng SwiftData cũ (`ZEXTENSION`, `ZREPOSITORY` trong `library.db`) và
/// `localStorage` từ `UserDefaults` sang `extension_store/`.
///
/// Gọi đồng bộ trong `FreeBookApp.init` **trước** `ModelContainer`: schema mới đã gỡ `@Model Extension` /
/// `Repository`, nên mở container xong là SwiftData có thể drop hai bảng — phải đọc trước đó.
///
/// An toàn:
/// - Luôn đọc từ bản chép `VACUUM INTO` (`legacy/library-pre-ext.sqlite`, gồm cả sách). Chép lỗi ⇒ đọc thẳng
///   `library.db` (vẫn trước khi container mở) để dữ liệu không mất.
/// - Thiếu bảng/cột bắt buộc ⇒ log `❌` liệt kê cột thật, **không** migrate, giữ bản chép để bản sau đọc lại.
/// - Ghi `repositories.json` → `local_storage.json` → `installed.json` (cờ `migratedFromLegacy` ghi **cuối**);
///   chỉ khi ghi đủ mới xoá khoá `vbook_ext_storage_*`. Lỗi giữa chừng ⇒ lần mở sau chạy lại.
/// - Mọi lần ghi **gộp** với dữ liệu đang có trong file (dữ liệu đang có thắng) — chạy lại sau một lần dở dang
///   hay sau khi `installed.json` bị cách ly cũng không đè mất kho/localStorage mới hơn.
enum LegacyExtensionSQLiteMigrator {
    private static let storageKeyPrefix = "vbook_ext_storage_"
    private static let globalStorageMarker = "global_"
    private static let globalNamespace = "global"

    private static let extensionColumns = [
        "ZPACKAGEID", "ZNAME", "ZAUTHOR", "ZVERSION", "ZSOURCEURL", "ZICONURL", "ZDESC", "ZTYPE", "ZLOCALE",
        "ZLOCALPATH", "ZCONFIGJSON", "ZDOWNLOADURL", "ZISPINNED", "ZINSTALLORIGIN", "ZREPOSITORY"
    ]
    private static let requiredExtensionColumns: Set<String> = ["ZPACKAGEID", "ZLOCALPATH"]
    private static let repositoryColumns = ["Z_PK", "ZURL", "ZNAME", "ZAUTHOR", "ZDESC"]
    private static let requiredRepositoryColumns: Set<String> = ["Z_PK", "ZURL"]

    /// Một tiện ích đọc được từ bảng cũ, kèm `localPath` tuyệt đối cũ để tìm khoá localStorage.
    private struct MigratedExtension {
        var value: Extension
        let legacyLocalPath: String
        let isPinned: Bool
    }

    static func runIfNeeded(databaseURL: URL) {
        let store = ExtensionIndexStore.shared
        let existing = store.readInstalled()
        if existing?.migratedFromLegacy == true { return }
        let existingExtensions = existing?.extensions ?? []

        let fm = FileManager.default
        let copyURL = ExtensionStorePaths.legacyDatabaseCopyURL
        let hasDatabase = fm.fileExists(atPath: databaseURL.path)
        var hasCopy = fm.fileExists(atPath: copyURL.path)

        guard hasDatabase || hasCopy else {
            // Cài mới: không có dữ liệu cũ nào ⇒ đánh dấu xong để không bao giờ phải chép DB ở lần mở sau.
            store.writeInstalledNow(existingExtensions, migratedFromLegacy: true)
            return
        }

        ExtensionStorePaths.ensureDirectories()
        if !hasCopy {
            hasCopy = LegacyExtensionSQLiteReader.makeCopy(of: databaseURL, to: copyURL)
            if !hasCopy {
                AppLogger.shared.log("❌ 🧩 [ExtMigrate] Không tạo được bản chép library.db — đọc thẳng library.db")
            }
        }
        let sourceURL = hasCopy ? copyURL : databaseURL
        guard let reader = LegacyExtensionSQLiteReader(url: sourceURL), let tables = reader.tableNames() else { return }

        let hasExtensionTable = tables.contains("ZEXTENSION")
        let hasRepositoryTable = tables.contains("ZREPOSITORY")
        guard hasExtensionTable || hasRepositoryTable else {
            // DB không có hai bảng cũ (cài mới, hoặc đã migrate ở nơi khác) ⇒ không có gì để chuyển.
            store.writeInstalledNow(existingExtensions, migratedFromLegacy: true)
            return
        }

        var repositories: [ExtensionRepositoryRecord] = []
        var repositoryUrlByPK: [Int64: String] = [:]
        if hasRepositoryTable {
            guard let loaded = readRepositories(reader) else { return }
            repositories = loaded.records
            repositoryUrlByPK = loaded.urlByPK
        }

        var migrated: [MigratedExtension] = []
        var skipped = 0
        if hasExtensionTable {
            guard let loaded = readExtensions(reader, repositoryUrlByPK: repositoryUrlByPK) else { return }
            migrated = loaded.extensions
            skipped = loaded.skipped
        }
        assignPinnedDates(&migrated)

        // (1) repositories.json — kho đang có trong file đứng trước, kho cũ chưa có thì nối sau.
        let existingRepos = store.readRepositories()
        var knownUrls = Set(existingRepos.map(\.url))
        let mergedRepos = existingRepos + repositories.filter { knownUrls.insert($0.url).inserted }
        guard store.writeRepositoriesNow(mergedRepos) else { return }

        // (2) local_storage.json
        let migratedStorage = collectLocalStorage(for: migrated)
        let keyCount = migratedStorage.values.reduce(0) { $0 + $1.count }
        if !migratedStorage.isEmpty {
            let localStore = ExtensionLocalStorageStore.shared
            let current = localStore.snapshot()
            var combined: [String: [String: String]] = [:]
            for (namespace, values) in migratedStorage {
                combined[namespace] = values.merging(current[namespace] ?? [:]) { _, existingValue in existingValue }
            }
            localStore.merge(combined)
            guard localStore.flush() else {
                AppLogger.shared.log("❌ 🧩 [ExtMigrate] Ghi local_storage.json thất bại — lần mở sau chạy lại")
                return
            }
        }

        // (3) installed.json — cờ `migratedFromLegacy` ghi cuối cùng.
        var knownIds = Set(existingExtensions.map(\.packageId))
        let newExtensions = migrated.map(\.value).filter { knownIds.insert($0.packageId).inserted }
        guard store.writeInstalledNow(existingExtensions + newExtensions, migratedFromLegacy: true) else {
            AppLogger.shared.log("❌ 🧩 [ExtMigrate] Ghi installed.json thất bại — lần mở sau chạy lại")
            return
        }

        removeLegacyStorageKeys()
        AppLogger.shared.log("ℹ️ 🧩 [ExtMigrate] Đã chuyển \(repositories.count) kho, \(newExtensions.count) tiện ích, \(keyCount) khoá localStorage (bỏ \(skipped) hàng) từ \(sourceURL.lastPathComponent)")
    }

    // MARK: - Đọc bảng cũ

    private static func readRepositories(
        _ reader: LegacyExtensionSQLiteReader
    ) -> (records: [ExtensionRepositoryRecord], urlByPK: [Int64: String])? {
        guard let columns = presentColumns(reader, table: "ZREPOSITORY", wanted: repositoryColumns, required: requiredRepositoryColumns),
              let rows = reader.rows(from: "ZREPOSITORY", columns: columns, orderBy: "Z_PK") else { return nil }
        let baseDate = Date()
        var records: [ExtensionRepositoryRecord] = []
        var urlByPK: [Int64: String] = [:]
        var seen = Set<String>()
        for row in rows {
            guard let url = trimmed(row["ZURL"]?.string), !url.isEmpty else { continue }
            if let pk = row["Z_PK"]?.int { urlByPK[pk] = url }
            guard seen.insert(url).inserted else { continue }
            records.append(ExtensionRepositoryRecord(
                url: url,
                name: nonEmpty(row["ZNAME"]?.string) ?? url,
                author: row["ZAUTHOR"]?.string,
                desc: row["ZDESC"]?.string,
                // Thứ tự Z_PK = thứ tự thêm kho; +1 ms mỗi kho để thứ tự ổn định.
                addedAt: baseDate.addingTimeInterval(Double(records.count) * 0.001)
            ))
        }
        return (records, urlByPK)
    }

    private static func readExtensions(
        _ reader: LegacyExtensionSQLiteReader,
        repositoryUrlByPK: [Int64: String]
    ) -> (extensions: [MigratedExtension], skipped: Int)? {
        guard let columns = presentColumns(reader, table: "ZEXTENSION", wanted: extensionColumns, required: requiredExtensionColumns),
              let rows = reader.rows(from: "ZEXTENSION", columns: columns) else { return nil }
        let now = Date()
        var result: [MigratedExtension] = []
        var seen = Set<String>()
        var skipped = 0
        for row in rows {
            // Chỉ hàng đã cài; mục kho chưa cài giờ dựng lại từ cache registry.
            guard let localPath = trimmed(row["ZLOCALPATH"]?.string), !localPath.isEmpty else { continue }
            let name = row["ZNAME"]?.string ?? ""
            guard let packageId = trimmed(row["ZPACKAGEID"]?.string), !packageId.isEmpty,
                  seen.insert(packageId).inserted else {
                AppLogger.shared.log("❌ 🧩 [ExtMigrate] Bỏ tiện ích \"\(name)\": packageId rỗng hoặc trùng")
                skipped += 1
                continue
            }
            guard let folder = ExtensionFolderLocator.folder(forAbsolutePath: localPath, packageId: packageId) else {
                AppLogger.shared.log("❌ 🧩 [ExtMigrate] Bỏ tiện ích \"\(name.isEmpty ? packageId : name)\": không tìm thấy thư mục có plugin.json")
                skipped += 1
                continue
            }
            let repositoryUrl = row["ZREPOSITORY"]?.int.flatMap { repositoryUrlByPK[$0] }
            let value = Extension(
                packageId: packageId,
                name: name.isEmpty ? packageId : name,
                author: row["ZAUTHOR"]?.string ?? "",
                version: row["ZVERSION"]?.int.map { Int($0) } ?? 1,
                sourceUrl: row["ZSOURCEURL"]?.string ?? "",
                iconUrl: row["ZICONURL"]?.string,
                desc: row["ZDESC"]?.string,
                type: nonEmpty(row["ZTYPE"]?.string) ?? ExtensionType.novel,
                locale: nonEmpty(row["ZLOCALE"]?.string) ?? "vi_VN",
                folder: folder,
                configJson: verbatimNonBlank(row["ZCONFIGJSON"]?.string) ?? "{}",
                downloadUrl: row["ZDOWNLOADURL"]?.string ?? "",
                repositoryUrl: repositoryUrl,
                installOrigin: nonEmpty(row["ZINSTALLORIGIN"]?.string) ?? Extension.installOriginRepository,
                installedAt: now
            )
            result.append(MigratedExtension(
                value: value,
                legacyLocalPath: localPath,
                isPinned: (row["ZISPINNED"]?.int ?? 0) != 0
            ))
        }
        result.sort { $0.value.name.localizedCaseInsensitiveCompare($1.value.name) == .orderedAscending }
        return (result, skipped)
    }

    /// Cột có thật trong bảng ∩ cột muốn đọc; thiếu cột bắt buộc ⇒ log `❌` kèm cột thật và trả `nil`.
    private static func presentColumns(
        _ reader: LegacyExtensionSQLiteReader,
        table: String,
        wanted: [String],
        required: Set<String>
    ) -> [String]? {
        guard let actual = reader.columns(of: table) else { return nil }
        let actualSet = Set(actual)
        let missing = required.subtracting(actualSet)
        guard missing.isEmpty else {
            AppLogger.shared.log("❌ 🧩 [ExtMigrate] Bảng \(table) thiếu cột \(missing.sorted().joined(separator: ", ")) — không migrate, giữ bản chép. Cột thật: \(actual.joined(separator: ", "))")
            return nil
        }
        return wanted.filter { actualSet.contains($0) }
    }

    /// `pinnedAt` = lúc migrate, +1 ms theo thứ tự tên (danh sách đã sắp A-Z) ⇒ nhóm ghim giữ đúng thứ tự cũ
    /// (ghim → A-Z).
    private static func assignPinnedDates(_ items: inout [MigratedExtension]) {
        let base = Date()
        var order = 0
        for index in items.indices where items[index].isPinned {
            items[index].value.pinnedAt = base.addingTimeInterval(Double(order) * 0.001)
            order += 1
        }
    }

    // MARK: - localStorage

    /// Gom khoá `"vbook_ext_storage_" + md5(path) + "_" + key` của từng tiện ích về namespace = `packageId`.
    /// Thử cả md5 của `ZLOCALPATH` cũ (path `JSExecutor` thật sự đã dùng — **thắng** khi trùng khoá) lẫn md5 của
    /// `localPath` tính lại từ gốc hiện tại. Khoá `..._global_...` (executor không có path) về namespace `global`.
    private static func collectLocalStorage(for items: [MigratedExtension]) -> [String: [String: String]] {
        var namespaceByHash: [String: (namespace: String, priority: Int)] = [:]
        for item in items {
            namespaceByHash[item.value.localPath.md5()] = (namespace: item.value.packageId, priority: 1)
        }
        for item in items {
            namespaceByHash[item.legacyLocalPath.md5()] = (namespace: item.value.packageId, priority: 2)
        }

        var result: [String: [String: String]] = [:]
        var priorities: [String: Int] = [:]
        for (fullKey, rawValue) in UserDefaults.standard.dictionaryRepresentation() {
            guard fullKey.hasPrefix(storageKeyPrefix), let value = rawValue as? String else { continue }
            let rest = String(fullKey.dropFirst(storageKeyPrefix.count))
            let namespace: String
            let key: String
            let priority: Int
            if rest.hasPrefix(globalStorageMarker) {
                namespace = globalNamespace
                key = String(rest.dropFirst(globalStorageMarker.count))
                priority = 2
            } else {
                // md5 hex luôn 32 ký tự, theo sau là "_".
                guard rest.count > 32 else { continue }
                let hash = String(rest.prefix(32))
                let remainder = rest.dropFirst(32)
                guard remainder.first == "_", let match = namespaceByHash[hash] else { continue }
                namespace = match.namespace
                key = String(remainder.dropFirst())
                priority = match.priority
            }
            let slot = namespace + "\u{0}" + key
            guard priority >= (priorities[slot] ?? 0) else { continue }
            priorities[slot] = priority
            result[namespace, default: [:]][key] = value
        }
        return result
    }

    /// Xoá **mọi** khoá `vbook_ext_storage_*` — kể cả của tiện ích đã gỡ/bản nháp, vốn không bao giờ được dọn.
    private static func removeLegacyStorageKeys() {
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(storageKeyPrefix) {
            defaults.removeObject(forKey: key)
        }
    }

    // MARK: - Helpers

    private static func trimmed(_ value: String?) -> String? {
        value?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value = trimmed(value), !value.isEmpty else { return nil }
        return value
    }

    /// Giữ nguyên văn (không trim) — cho `configJson`; chỉ coi chuỗi toàn khoảng trắng là rỗng.
    private static func verbatimNonBlank(_ value: String?) -> String? {
        guard let value, nonEmpty(value) != nil else { return nil }
        return value
    }
}
