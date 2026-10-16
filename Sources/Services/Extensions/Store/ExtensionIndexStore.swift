import Foundation

/// IO tầng thấp cho `installed.json`, `repositories.json` và `registry/*.json`.
///
/// - Đọc **đồng bộ** (index ~50 KB, đọc lúc khởi động trước khi UI cần).
/// - Ghi atomic trên **một** serial queue nền ⇒ các lần ghi không chen nhau và luôn theo đúng thứ tự gọi.
///   Biến thể `...Now` chạy `queue.sync` — chỉ dành cho migrator và flush khi vào background (chờ cả các
///   lần ghi async đang xếp hàng).
/// - Đọc cũng đi qua `queue.sync` để không bao giờ đọc giữa một lần ghi đang chờ.
///
/// Không giữ trạng thái nghiệp vụ: nguồn sự thật là `ExtensionLibraryRepository`. Thứ duy nhất được nhớ là
/// cờ `migratedFromLegacy` để mỗi lần ghi `installed.json` giữ nguyên cờ (repository không cần biết tới nó).
public final class ExtensionIndexStore: @unchecked Sendable {
    public static let shared = ExtensionIndexStore()

    private let queue = DispatchQueue(label: "FreeBook.ExtensionIndexStore", qos: .utility)
    /// Chỉ truy cập trên `queue`.
    private var migratedFromLegacy = false

    private init() {}

    // MARK: - Đọc

    /// `nil` khi `installed.json` chưa có hoặc hỏng (đã cách ly).
    public func readInstalled() -> ExtensionStoreEnvelope.Installed? {
        queue.sync {
            let envelope = ExtensionStoreFileIO.read(
                ExtensionStoreEnvelope.Installed.self,
                from: ExtensionStorePaths.installedURL,
                label: "installed.json"
            )
            migratedFromLegacy = envelope?.migratedFromLegacy ?? false
            return envelope
        }
    }

    /// Theo thứ tự thêm kho; rỗng khi file chưa có hoặc hỏng.
    public func readRepositories() -> [ExtensionRepositoryRecord] {
        queue.sync {
            ExtensionStoreFileIO.read(
                ExtensionStoreEnvelope.Repositories.self,
                from: ExtensionStorePaths.repositoriesURL,
                label: "repositories.json"
            )?.repositories ?? []
        }
    }

    /// Mọi cache registry đọc được, khoá theo URL kho. File hỏng bị cách ly, kho đó coi như chưa có cache.
    public func readRegistries() -> [String: ExtensionRegistrySnapshot] {
        queue.sync {
            let directory = ExtensionStorePaths.registryDirectory
            let files = (try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )) ?? []
            var result: [String: ExtensionRegistrySnapshot] = [:]
            for file in files where file.pathExtension == "json" {
                guard let envelope = ExtensionStoreFileIO.read(
                    ExtensionStoreEnvelope.Registry.self,
                    from: file,
                    label: "registry/\(file.lastPathComponent)"
                ) else { continue }
                result[envelope.snapshot.url] = envelope.snapshot
            }
            return result
        }
    }

    // MARK: - Ghi (async trên queue nền)

    /// Ghi `installed.json`, giữ nguyên cờ `migratedFromLegacy` hiện có.
    public func writeInstalled(_ extensions: [Extension]) {
        queue.async { [weak self] in
            _ = self?.performWriteInstalled(extensions, migratedFromLegacy: nil)
        }
    }

    public func writeRepositories(_ repositories: [ExtensionRepositoryRecord]) {
        queue.async {
            _ = ExtensionStoreFileIO.write(
                ExtensionStoreEnvelope.Repositories(repositories: repositories),
                to: ExtensionStorePaths.repositoriesURL,
                label: "repositories.json"
            )
        }
    }

    public func writeRegistry(_ snapshot: ExtensionRegistrySnapshot) {
        queue.async {
            _ = ExtensionStoreFileIO.write(
                ExtensionStoreEnvelope.Registry(snapshot: snapshot),
                to: ExtensionStorePaths.registryURL(forRepositoryUrl: snapshot.url),
                label: "registry của \(snapshot.url)"
            )
        }
    }

    public func removeRegistry(url: String) {
        queue.async {
            _ = ExtensionStoreFileIO.remove(
                at: ExtensionStorePaths.registryURL(forRepositoryUrl: url),
                label: "registry của \(url)"
            )
        }
    }

    // MARK: - Ghi đồng bộ (migrator / flush)

    /// `migratedFromLegacy == nil` ⇒ giữ cờ hiện có. Trả `false` khi ghi lỗi (đã log `❌`).
    @discardableResult
    public func writeInstalledNow(_ extensions: [Extension], migratedFromLegacy: Bool? = nil) -> Bool {
        queue.sync { performWriteInstalled(extensions, migratedFromLegacy: migratedFromLegacy) }
    }

    @discardableResult
    public func writeRepositoriesNow(_ repositories: [ExtensionRepositoryRecord]) -> Bool {
        queue.sync {
            ExtensionStoreFileIO.write(
                ExtensionStoreEnvelope.Repositories(repositories: repositories),
                to: ExtensionStorePaths.repositoriesURL,
                label: "repositories.json"
            )
        }
    }

    /// Chờ mọi lần ghi async đã xếp hàng chạy xong.
    public func waitForPendingWrites() {
        queue.sync {}
    }

    /// Chỉ gọi trên `queue`.
    private func performWriteInstalled(_ extensions: [Extension], migratedFromLegacy flag: Bool?) -> Bool {
        let resolvedFlag = flag ?? migratedFromLegacy
        let envelope = ExtensionStoreEnvelope.Installed(migratedFromLegacy: resolvedFlag, extensions: extensions)
        let ok = ExtensionStoreFileIO.write(envelope, to: ExtensionStorePaths.installedURL, label: "installed.json")
        if ok { migratedFromLegacy = resolvedFlag }
        return ok
    }
}
