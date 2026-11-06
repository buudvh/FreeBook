import Foundation
import Observation

/// Nguồn sự thật **duy nhất** cho tiện ích đã cài, danh sách kho và cache registry — thay `@Model Extension` /
/// `@Model Repository` của SwiftData.
///
/// - View đọc trực tiếp các thuộc tính `@Observable` (`installed`, `catalog`, `repositories`) trên MainActor.
/// - Tầng nền đọc qua `nonisolated static func` (`snapshot(packageId:)`, `installedSnapshot()`…) — bảng chụp
///   `ExtensionLibrarySnapshotTable` có lock, được cập nhật sau **mỗi** mutation.
/// - Chỉ `ExtensionTransactionCoordinator` được gọi mutation (`internal`). Mỗi mutation tính lại `remoteVersion`,
///   `catalog`, bảng chụp rồi lên lịch ghi file qua `ExtensionIndexStore` (queue nền).
///
/// `catalog` = đã cài ∪ mục registry chưa cài, được **tính lại và lưu** sau mỗi mutation (không tính trong
/// getter) để View render không phải dựng lại danh sách.
@MainActor
@Observable
public final class ExtensionLibraryRepository {
    public static let shared = ExtensionLibraryRepository()

    /// Tiện ích đã cài, đã gắn `remoteVersion` từ cache registry.
    public private(set) var installed: [Extension] = []
    /// Theo thứ tự thêm kho.
    public private(set) var repositories: [ExtensionRepositoryRecord] = []
    /// Cache registry, khoá theo URL kho.
    public private(set) var registries: [String: ExtensionRegistrySnapshot] = [:]
    /// Đã cài ∪ mục registry chưa cài (`folder = ""`), dedupe theo **tên + tác giả** (`ExtensionCatalogIdentity`,
    /// 1.3.753): đã cài thắng; giữa các kho, kho đứng trước trong `repositories` thắng. Cùng tên khác tác giả ⇒ hai
    /// hàng, mục sau mang mã `<mã>__<tác giả>`. `packageId` trong danh sách luôn duy nhất.
    public private(set) var catalog: [Extension] = []

    /// Chỉ mục của `registries` (cùng khoá URL kho), dựng lại khi cache một kho đổi — tra mục registry của một tiện
    /// ích mà không quét lại cả kho ở mỗi lần `rebuild`.
    @ObservationIgnored private var registryIndexes: [String: ExtensionCatalogIdentity.RegistryIndex] = [:]

    /// Lần ghi `installed.json` đang chờ debounce (chỉ cho `lastUsedAt`).
    @ObservationIgnored private var pendingInstalledWrite: Task<Void, Never>?

    /// Gom ghi `lastUsedAt`: duyệt qua nhiều nguồn liên tiếp chỉ ghi file một lần.
    private static let lastUsedWriteDelayNanoseconds: UInt64 = 3_000_000_000

    private init() {}

    // MARK: - Nạp / flush

    /// Đọc đồng bộ 3 loại file lúc khởi động (sau `LegacyExtensionSQLiteMigrator`).
    public func load() {
        let store = ExtensionIndexStore.shared
        let index = store.readInstalled()
        repositories = store.readRepositories()
        registries = store.readRegistries()
        registryIndexes = registries.mapValues { ExtensionCatalogIdentity.RegistryIndex(items: $0.items) }
        rebuild(installedList: index?.extensions ?? [])
        AppLogger.shared.log("ℹ️ 🧩 [ExtStore] Nạp \(installed.count) tiện ích đã cài, \(repositories.count) kho, \(registries.count) cache registry")
    }

    /// Ghi ngay mọi thứ đang chờ (installed + localStorage) — gọi khi app vào background.
    public func flush() {
        if let pending = pendingInstalledWrite {
            pending.cancel()
            pendingInstalledWrite = nil
            ExtensionIndexStore.shared.writeInstalledNow(installed)
        } else {
            ExtensionIndexStore.shared.waitForPendingWrites()
        }
        ExtensionLocalStorageStore.shared.flush()
    }

    // MARK: - Tra cứu (MainActor)

    public func installedExtension(packageId: String) -> Extension? {
        installed.first { $0.packageId == packageId }
    }

    /// Gồm cả mục **chưa cài** của registry — kệ sách/Reader dùng để lấy tên/icon nguồn.
    public func catalogExtension(packageId: String) -> Extension? {
        catalog.first { $0.packageId == packageId }
    }

    /// Dòng registry của một tiện ích (đã cài hoặc mục danh mục) trong cache **chính** kho `repositoryUrl` của nó:
    /// tên + tác giả → `packageId` (mã trơn hoặc `<mã>__<tác giả>`). `nil` khi không thuộc kho nào, kho chưa có cache
    /// hoặc không khớp.
    public func registryItem(for ext: Extension) -> ExtensionRegistryItem? {
        registryItem(repositoryUrl: ext.repositoryUrl, packageId: ext.packageId, name: ext.name, author: ext.author)
    }

    public func registryItem(repositoryUrl: String?, packageId: String, name: String, author: String?) -> ExtensionRegistryItem? {
        guard let repositoryUrl, let index = registryIndexes[repositoryUrl] else { return nil }
        return index.item(packageId: packageId, name: name, author: author)
    }

    // MARK: - Tra cứu từ tầng nền (không cần await)

    /// Tiện ích **đã cài** theo `packageId`.
    nonisolated public static func snapshot(packageId: String) -> Extension? {
        ExtensionLibrarySnapshotTable.shared.installedExtension(packageId: packageId)
    }

    /// Như `catalogExtension(packageId:)` nhưng gọi được từ thread bất kỳ — gồm cả mục chưa cài.
    nonisolated public static func catalogSnapshot(packageId: String) -> Extension? {
        ExtensionLibrarySnapshotTable.shared.catalogExtension(packageId: packageId)
    }

    nonisolated public static func installedSnapshot() -> [Extension] {
        ExtensionLibrarySnapshotTable.shared.installed()
    }

    nonisolated public static func repositoriesSnapshot() -> [ExtensionRepositoryRecord] {
        ExtensionLibrarySnapshotTable.shared.repositories()
    }

    /// `localPath` tuyệt đối → `packageId` của tiện ích đã cài có đúng `localPath` đó (so sau
    /// `standardizedFileURL`). `nil` với path ngoài `extensions/` (bản nháp debug) hoặc chưa cài.
    nonisolated public static func packageId(forLocalPath path: String) -> String? {
        ExtensionLibrarySnapshotTable.shared.packageId(forLocalPath: path)
    }

    // MARK: - Mutation (chỉ ExtensionTransactionCoordinator)

    /// Thay toàn bộ danh sách đã cài. `debounced == true` chỉ dành cho `lastUsedAt` (ghi file sau ~3 s).
    func setInstalled(_ list: [Extension], debounced: Bool = false) {
        rebuild(installedList: list)
        persistInstalled(debounced: debounced)
    }

    func setRepositories(_ list: [ExtensionRepositoryRecord]) {
        repositories = list
        rebuild(installedList: installed)
        ExtensionIndexStore.shared.writeRepositories(list)
    }

    func setRegistry(_ snapshot: ExtensionRegistrySnapshot) {
        registries[snapshot.url] = snapshot
        registryIndexes[snapshot.url] = ExtensionCatalogIdentity.RegistryIndex(items: snapshot.items)
        rebuild(installedList: installed)
        ExtensionIndexStore.shared.writeRegistry(snapshot)
    }

    func removeRegistry(url: String) {
        let hadCache = registries.removeValue(forKey: url) != nil
        registryIndexes.removeValue(forKey: url)
        if hadCache { rebuild(installedList: installed) }
        ExtensionIndexStore.shared.removeRegistry(url: url)
    }

    // MARK: - Dẫn xuất

    private func rebuild(installedList: [Extension]) {
        let activeRepositories = Set(repositories.map(\.url))
        var attached = installedList
        for i in attached.indices {
            attached[i].remoteVersion = remoteVersion(for: attached[i], activeRepositories: activeRepositories)
        }
        installed = attached
        let nextCatalog = buildCatalog(installed: attached)
        catalog = nextCatalog
        ExtensionLibrarySnapshotTable.shared.update(installed: attached, catalog: nextCatalog, repositories: repositories)
    }

    /// Chỉ registry của **chính** `repositoryUrl` (kho còn trong `repositories`). Không fallback sang kho khác: tiện ích
    /// zip/debug (`repositoryUrl == nil`) hay tiện ích của kho A trùng tên với kho B sẽ bị báo "có cập nhật" mà nút
    /// cập nhật lại tải từ nguồn sai (hoặc ghi đè bản debug). Trong kho, ghép theo tên + tác giả (1.3.753).
    private func remoteVersion(for ext: Extension, activeRepositories: Set<String>) -> Int? {
        guard let repoUrl = ext.repositoryUrl, activeRepositories.contains(repoUrl) else { return nil }
        return registryItem(for: ext)?.version
    }

    /// Đã cài đứng trước; mục registry trùng **tên + tác giả** với một tiện ích đã có thì bỏ, còn lại cấp mã duy nhất
    /// (`ExtensionCatalogIdentity.packageId`). Tiện ích đã cài đánh dấu cả khoá của chính nó lẫn khoá dòng registry
    /// khớp nó trong kho của nó — tác giả trong `plugin.json` khác chữ với registry không làm hiện thêm một hàng.
    private func buildCatalog(installed: [Extension]) -> [Extension] {
        var takenIds = Set(installed.map(\.packageId))
        var seenKeys = Set<String>()
        for ext in installed {
            seenKeys.insert(ExtensionCatalogIdentity.key(name: ext.name, author: ext.author))
            if let item = registryItem(for: ext) {
                seenKeys.insert(ExtensionCatalogIdentity.key(name: item.name, author: item.author))
            }
        }
        var result = installed
        for repo in repositories {
            guard let index = registryIndexes[repo.url] else { continue }
            for entry in index.entries {
                guard !entry.base.isEmpty, seenKeys.insert(entry.key).inserted,
                      let pid = ExtensionCatalogIdentity.packageId(base: entry.base, author: entry.item.author, taken: takenIds)
                else { continue }
                takenIds.insert(pid)
                result.append(Self.catalogEntry(from: entry.item, packageId: pid, repositoryUrl: repo.url))
            }
        }
        return result
    }

    /// Dựng mục catalog chưa cài từ một dòng registry. Registry thiếu trường ⇒ mặc định (`vi_VN`/`novel`).
    nonisolated private static func catalogEntry(
        from item: ExtensionRegistryItem,
        packageId: String,
        repositoryUrl: String
    ) -> Extension {
        Extension(
            packageId: packageId,
            name: item.name,
            author: item.author ?? "",
            version: item.version ?? 1,
            sourceUrl: item.source ?? "",
            iconUrl: item.icon,
            desc: item.description,
            type: nonEmpty(item.type) ?? ExtensionType.novel,
            locale: nonEmpty(item.locale) ?? "vi_VN",
            folder: "",
            downloadUrl: item.path,
            repositoryUrl: repositoryUrl,
            installOrigin: Extension.installOriginRepository,
            remoteVersion: item.version,
            isNsfw: item.isNsfw
        )
    }

    nonisolated private static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    // MARK: - Ghi file

    private func persistInstalled(debounced: Bool) {
        pendingInstalledWrite?.cancel()
        pendingInstalledWrite = nil
        guard debounced else {
            ExtensionIndexStore.shared.writeInstalled(installed)
            return
        }
        pendingInstalledWrite = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.lastUsedWriteDelayNanoseconds)
            guard !Task.isCancelled, let self else { return }
            self.pendingInstalledWrite = nil
            ExtensionIndexStore.shared.writeInstalled(self.installed)
        }
    }
}
