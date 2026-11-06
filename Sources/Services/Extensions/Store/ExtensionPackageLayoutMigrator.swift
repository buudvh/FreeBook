import Foundation

/// Chuyển **một lần** gói tiện ích từ bố cục thư mục (`extensions/<packageId>/`) sang bố cục một file
/// (`extensions/js/<packageId>.json`, `extensions/legado/<packageId>.json`), rồi dọn thư mục cũ trên nền.
///
/// Gọi trong `FreeBookApp.init`: `runIfNeeded()` ngay sau `LegacyExtensionSQLiteMigrator`, **trước**
/// `ExtensionLibraryRepository.shared.load()`; `scheduleCleanup()` ngay sau `load()`.
///
/// **Không có cờ hoàn tất**: `ExtensionIndexStore.performWriteInstalled` dựng lại envelope chỉ với
/// `migratedFromLegacy`, cờ mới sẽ mất ở lần ghi thường đầu tiên. Thay vào đó xét **từng bản ghi**: `folder` không phải
/// file gói (`ExtensionFolderLocator.isPackageFileFolder`) ⇒ cần chuyển. Hết bản ghi cần chuyển ⇒ chỉ một lượt duyệt mảng.
///
/// Các bước (chết giữa chừng ở đâu cũng chạy lại được — thư mục cũ chỉ bị xoá **sau** khi `installed.json` đã ghi):
/// 1. Thư mục cũ trùng tên gốc mới (`extensions/js/`, `extensions/legado/` của một tiện ích — vd tiện ích JS tên "Legado"
///    có `packageId` `legado`) ⇒ đổi sang tên **cố định** `<tên>.legacy` rồi ghi `installed.json` **ngay** (trường hợp hiếm;
///    phải ghi trước khi gốc mới được tạo, nếu không bản ghi sẽ trỏ vào gốc mới). Chết giữa đổi tên và ghi ⇒ lần sau thấy
///    `<tên>.legacy` mà không còn `<tên>` thì chỉ trỏ bản ghi sang đó rồi ghi, không đổi tên lại.
/// 2. JS: gom thư mục `plugin.json` của bản ghi ⇒ `js/<id>.json` (ghi đè). Legado: **hard link** `source.json` ⇒
///    `legado/<id>.json` (đích có sẵn thì xoá trước), link lỗi thì chép. Không parse nguồn Legado nào; `isNsfw` của bản
///    ghi giữ nguyên (sửa cờ ở `LegadoSourceRepository.readAllSummaries`). Thư mục cũ còn nguyên.
/// 3. Ghi `installed.json` **một lần** với các `folder` mới. Lỗi ⇒ không dọn gì ở lần mở này.
/// 4. `scheduleCleanup`: trên luồng nền, quét **một cấp** `extensions/` — mục không phải `js`/`legado`, không bản ghi nào
///    trỏ tới, không phải thư mục tạm đang thay của bản nháp ⇒ xoá (gồm `common/`). Xoá dở thì lần sau xoá tiếp. Chỉ chạy
///    khi lần mở này đọc được `installed.json` (hỏng / cách ly ⇒ danh sách rỗng ⇒ quét sẽ xoá sạch thư mục chưa chuyển),
///    và không còn bản cách ly `installed.json.corrupt-*` nào (index có thể đã dựng lại từ rỗng sau lần hỏng đó).
///
/// Bản ghi chuyển lỗi (hoặc `packageId` không làm được tên file) giữ nguyên `folder` cũ — vẫn chạy nhờ bộ đọc ba dạng — và
/// được đếm trong **một** dòng log `❌ [ExtLayout]` mỗi lần mở app.
enum ExtensionPackageLayoutMigrator {
    /// Lần mở này được phép dọn (`installed.json` đọc được và mọi lần ghi của nó đã thành công). Chỉ đọc/ghi trên main.
    private static var cleanupAllowed = false

    private static var root: URL { ExtensionFolderLocator.extensionsRoot }
    private static var newRootNames: [String] { [ExtensionFolderLocator.jsFolderName, ExtensionFolderLocator.legadoFolderName] }

    // MARK: - Chuyển (đồng bộ, lúc khởi động)

    static func runIfNeeded() {
        let store = ExtensionIndexStore.shared
        guard let envelope = store.readInstalled() else { return }
        var list = envelope.extensions
        let pending = list.indices.filter { needsMigration(list[$0]) }
        guard !pending.isEmpty else {
            cleanupAllowed = true
            return
        }

        let started = Date()
        var blockedRoots = Set<String>()
        guard resolveRootConflicts(in: &list, blocked: &blockedRoots, store: store) else { return }
        // Tạo hai gốc một lần (không tạo lại theo từng nguồn Legado). Lỗi ⇒ từng bản ghi báo lỗi riêng ở bước 2.
        for directory in [ExtensionFolderLocator.jsRoot, ExtensionFolderLocator.legadoRoot] {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        var migrated = 0
        var failures: [String] = []
        for index in pending {
            let ext = list[index]
            if let first = topLevelName(ext.folder), blockedRoots.contains(first) {
                failures.append("\(ext.packageId) (trùng thư mục gốc mới)")
                continue
            }
            do {
                list[index].folder = try migrate(ext)
                migrated += 1
            } catch {
                failures.append("\(ext.packageId) (\(error.localizedDescription))")
            }
        }

        if migrated > 0, !store.writeInstalledNow(list) {
            AppLogger.shared.log("❌ 🧩 [ExtLayout] Không ghi được installed.json sau khi chuyển \(migrated) gói — giữ thư mục cũ, lần mở sau chạy lại")
            return
        }
        cleanupAllowed = true
        let elapsed = String(format: "%.2f", Date().timeIntervalSince(started))
        AppLogger.shared.log("ℹ️ 🧩 [ExtLayout] Đã chuyển \(migrated)/\(pending.count) gói sang bố cục một file trong \(elapsed)s")
        if !failures.isEmpty {
            AppLogger.shared.log("❌ 🧩 [ExtLayout] Giữ dạng thư mục cho \(failures.count) gói: \(failures.prefix(10).joined(separator: ", "))")
        }
    }

    static func needsMigration(_ ext: Extension) -> Bool {
        !ext.folder.isEmpty && !ExtensionFolderLocator.isPackageFileFolder(ext.folder)
    }

    /// Chuyển một bản ghi; trả `folder` mới. Ném ⇒ bản ghi giữ nguyên.
    private static func migrate(_ ext: Extension) throws -> String {
        let source = URL(fileURLWithPath: ExtensionFolderLocator.absolutePath(forFolder: ext.folder), isDirectory: true)
        if LegadoSourceIdentity.isLegado(ext) {
            guard let target = ExtensionFolderLocator.legadoPackageURL(packageId: ext.packageId) else {
                throw ExtensionPackageWriter.WriteError.unsafePackageId(ext.packageId)
            }
            let sourceFile = source.appendingPathComponent(ExtensionPackageReader.legadoSourceFileName)
            try linkOrCopy(sourceFile, to: target)
            return ExtensionFolderLocator.legadoFolderName + "/" + target.lastPathComponent
        }
        let target = try ExtensionPackageWriter.install(directory: source, packageId: ext.packageId)
        return ExtensionFolderLocator.jsFolderName + "/" + target.lastPathComponent
    }

    /// Hard link (rẻ như đổi tên, không chép); lỗi thì chép. Đích có sẵn (lần trước chết giữa chừng) ⇒ xoá trước.
    private static func linkOrCopy(_ source: URL, to target: URL) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: source.path) else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: source.lastPathComponent])
        }
        if fileManager.fileExists(atPath: target.path) {
            try fileManager.removeItem(at: target)
        }
        do {
            try fileManager.linkItem(at: source, to: target)
        } catch {
            try fileManager.copyItem(at: source, to: target)
        }
    }

    /// Bước 1. Thư mục cũ tên `js` / `legado` (có `plugin.json`, hoặc là gốc `folder` của bản ghi chưa chuyển) ⇒ đổi sang
    /// `<tên>.legacy` (hoặc chỉ trỏ bản ghi sang đó nếu lần trước đã đổi mà chưa kịp ghi) rồi ghi `installed.json` ngay.
    /// Không xử lý được (thư mục đó đồng thời đã là gốc mới, cả hai tên cùng có, đổi tên lỗi) ⇒ chỉ chặn gốc đó (`blocked`:
    /// các bản ghi dưới nó giữ dạng cũ), gốc kia và các bản ghi khác vẫn chuyển. Trả `false` chỉ khi ghi sau khi đã trỏ bản
    /// ghi sang tên mới bị lỗi ⇒ bỏ cả lượt chuyển lẫn lượt dọn của lần mở này.
    private static func resolveRootConflicts(
        in list: inout [Extension],
        blocked: inout Set<String>,
        store: ExtensionIndexStore
    ) -> Bool {
        let fileManager = FileManager.default
        var renamed: [(from: URL, to: URL)] = []
        var remapped = false
        for name in newRootNames {
            let directory = root.appendingPathComponent(name, isDirectory: true)
            let parkedName = name + ".legacy"
            let parked = root.appendingPathComponent(parkedName, isDirectory: true)
            let hasManifest = fileManager.fileExists(
                atPath: directory.appendingPathComponent(ExtensionPackageBundle.manifestPath).path
            )
            let hasLegacyUse = hasManifest || list.contains { needsMigration($0) && topLevelName($0.folder) == name }
            guard hasLegacyUse else { continue }
            if list.contains(where: { !needsMigration($0) && topLevelName($0.folder) == name }) {
                blocked.insert(name)
                continue
            }
            let directoryExists = fileManager.fileExists(atPath: directory.path)
            let parkedExists = fileManager.fileExists(atPath: parked.path)
            if directoryExists && parkedExists {
                AppLogger.shared.log("❌ 🧩 [ExtLayout] Có cả \(name)/ lẫn \(parkedName)/ — giữ nguyên các gói dưới \(name)/")
                blocked.insert(name)
                continue
            }
            if directoryExists {
                do {
                    try fileManager.moveItem(at: directory, to: parked)
                } catch {
                    AppLogger.shared.log("❌ 🧩 [ExtLayout] Không đổi tên được thư mục cũ \(name)/: \(error.localizedDescription)")
                    blocked.insert(name)
                    continue
                }
                renamed.append((directory, parked))
            }
            for index in list.indices where needsMigration(list[index]) && topLevelName(list[index].folder) == name {
                list[index].folder = parkedName + list[index].folder.dropFirst(name.count)
                remapped = true
            }
        }
        guard remapped || !renamed.isEmpty else { return true }
        if store.writeInstalledNow(list) { return true }
        // Ghi lỗi: trả tên cũ để `installed.json` (vẫn ghi tên cũ) còn đúng.
        for pair in renamed.reversed() {
            do {
                try FileManager.default.moveItem(at: pair.to, to: pair.from)
            } catch {
                AppLogger.shared.log("❌ 🧩 [ExtLayout] Không trả lại tên \(pair.from.lastPathComponent)/, dữ liệu còn ở \(pair.to.lastPathComponent)/: \(error.localizedDescription)")
            }
        }
        AppLogger.shared.log("❌ 🧩 [ExtLayout] Không ghi được installed.json sau khi đổi tên thư mục trùng gốc mới")
        return false
    }

    private static func topLevelName(_ folder: String) -> String? {
        let trimmed = folder.trimmingCharacters(in: CharacterSet(charactersIn: "/").union(.whitespacesAndNewlines))
        guard let first = trimmed.split(separator: "/").first else { return nil }
        return String(first)
    }

    // MARK: - Dọn (nền)

    /// Gọi ngay sau `ExtensionLibraryRepository.shared.load()`. Danh sách mục còn được trỏ tới lấy từ bảng chụp vừa nạp
    /// (đúng nội dung `installed.json` trên đĩa), không từ danh sách trong RAM của bước chuyển.
    static func scheduleCleanup() {
        guard cleanupAllowed, !hasQuarantinedIndex() else { return }
        let referenced = Set(ExtensionLibraryRepository.installedSnapshot().compactMap { topLevelName($0.folder) })
        DispatchQueue.global(qos: .utility).async {
            Self.sweep(keeping: referenced)
        }
    }

    private static func sweep(keeping referenced: Set<String>) {
        let fileManager = FileManager.default
        guard let names = try? fileManager.contentsOfDirectory(atPath: root.path) else { return }
        var removed = 0
        var failed: [String] = []
        for name in names where shouldRemove(name, referenced: referenced) {
            do {
                try fileManager.removeItem(at: root.appendingPathComponent(name))
                removed += 1
            } catch {
                failed.append(name)
            }
        }
        if removed > 0 {
            AppLogger.shared.log("🧹 🧩 [ExtLayout] Đã xoá \(removed) thư mục cũ trong extensions/")
        }
        if !failed.isEmpty {
            AppLogger.shared.log("❌ 🧩 [ExtLayout] Chưa xoá được \(failed.count) mục cũ (lần mở sau xoá tiếp): \(failed.prefix(10).joined(separator: ", "))")
        }
    }

    /// `installed.json` từng hỏng và còn bản cách ly `installed.json.corrupt-*` (giữ để cứu tay) ⇒ không dọn: index hiện
    /// tại có thể đã dựng lại từ rỗng, thư mục cũ "không ai trỏ tới" lại là thứ bản cách ly còn trỏ tới.
    private static func hasQuarantinedIndex() -> Bool {
        let prefix = ExtensionStorePaths.installedURL.lastPathComponent + ".corrupt-"
        let names = (try? FileManager.default.contentsOfDirectory(atPath: ExtensionStorePaths.rootURL.path)) ?? []
        return names.contains { $0.hasPrefix(prefix) }
    }

    /// Bỏ qua: hai gốc mới, mục còn bản ghi trỏ tới, mục ẩn, và thư mục tạm đang thay của bản nháp debug
    /// (`<tên>.incoming-<uuid>` / `<tên>.rollback-<uuid>`, `ExtensionDraftInstaller`).
    private static func shouldRemove(_ name: String, referenced: Set<String>) -> Bool {
        guard !newRootNames.contains(name), !referenced.contains(name), !name.hasPrefix(".") else { return false }
        return !name.contains(".incoming-") && !name.contains(".rollback-")
    }
}
