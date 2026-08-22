import Foundation

/// Dựng sẵn danh sách `UpsertExtensionCommand` cho một kho tiện ích.
///
/// Trước đây `RepositoryManagerView.syncExtensions` vừa tải `plugin.json` **tuần tự** cho từng ext
/// vừa `context.save()` một lần cho mỗi ext, tất cả trên MainActor — kho 60 ext là 60 request nối đuôi
/// nhau cộng 60 transaction, mỗi transaction lại kéo `@Query` render lại. Builder này gánh phần tải
/// và resolve metadata ra khỏi MainActor, chạy song song có giới hạn, rồi trả về danh sách command
/// để caller ghi **một lượt duy nhất**.
///
/// Thứ tự fallback của từng field giữ y nguyên hành vi cũ:
/// `plugin.json` cục bộ → `plugin.json` trên mạng → dòng registry → mặc định.
public struct ExtensionSyncCommandBuilder: Sendable {

    /// Một dòng registry đã kèm `localPath` của bản đã cài — chụp trên MainActor trước khi rời main
    /// để builder không phải đọc SwiftData ở tầng nền.
    public struct Input: Sendable {
        public let name: String
        public let path: String
        public let author: String?
        public let version: Int?
        public let source: String?
        public let icon: String?
        public let desc: String?
        public let type: String?
        public let locale: String?
        public let existingLocalPath: String

        public init(item: ExtensionRegistryItem, existingLocalPath: String) {
            self.name = item.name
            self.path = item.path
            self.author = item.author
            self.version = item.version
            self.source = item.source
            self.icon = item.icon
            self.desc = item.description
            self.type = item.type
            self.locale = item.locale
            self.existingLocalPath = existingLocalPath
        }
    }

    /// Metadata đọc được từ `plugin.json` (cục bộ hoặc trên mạng); `nil` nghĩa là không có, phải fallback.
    private struct Metadata: Sendable {
        var author: String?
        var locale: String?
        var type: String?
        var version: Int?
        var source: String?
    }

    /// Số lượt tải `plugin.json` chạy đồng thời. Giữ nhỏ để không làm ngộp máy chủ kho.
    public static let defaultConcurrency = 6

    /// Timeout cho mỗi request `plugin.json`. Mặc định của `URLSession` là 60 s — quá dài khi
    /// một kho có vài chục ext và chỉ vài file lỗi.
    public static let requestTimeout: TimeInterval = 10

    public static func packageId(forName name: String) -> String {
        name.lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Trả về command theo **đúng thứ tự** của `inputs`.
    public static func build(
        inputs: [Input],
        repositoryUrl: String,
        maxConcurrent: Int = defaultConcurrency
    ) async -> [UpsertExtensionCommand] {
        guard !inputs.isEmpty else { return [] }
        let limit = max(1, min(maxConcurrent, inputs.count))
        var results = [UpsertExtensionCommand?](repeating: nil, count: inputs.count)

        await withTaskGroup(of: (Int, UpsertExtensionCommand).self) { group in
            var nextIndex = 0
            while nextIndex < limit {
                let index = nextIndex
                let input = inputs[index]
                group.addTask { (index, await command(for: input, repositoryUrl: repositoryUrl)) }
                nextIndex += 1
            }

            while let (index, builtCommand) = await group.next() {
                results[index] = builtCommand
                guard nextIndex < inputs.count else { continue }
                let queuedIndex = nextIndex
                let queuedInput = inputs[queuedIndex]
                group.addTask { (queuedIndex, await command(for: queuedInput, repositoryUrl: repositoryUrl)) }
                nextIndex += 1
            }
        }

        return results.compactMap { $0 }
    }

    private static func command(for input: Input, repositoryUrl: String) async -> UpsertExtensionCommand {
        var metadata = localMetadata(forLocalPath: input.existingLocalPath)
        if metadata == nil {
            metadata = await remoteMetadata(for: input)
        }
        let resolved = metadata ?? Metadata()

        let repoRemoteVersion = input.version ?? 1
        let finalAuthor = resolved.author ?? input.author ?? ""
        let finalLocale = resolved.locale ?? input.locale ?? "vi_VN"
        let finalType = resolved.type ?? input.type ?? ExtensionType.novel
        let finalVersion = resolved.version ?? input.version ?? 1
        let finalSource = resolved.source ?? input.source ?? ""

        return UpsertExtensionCommand(
            packageId: packageId(forName: input.name),
            name: input.name,
            author: finalAuthor,
            version: finalVersion,
            remoteVersion: repoRemoteVersion,
            sourceUrl: finalSource,
            iconUrl: input.icon,
            desc: input.desc,
            type: finalType,
            locale: finalLocale,
            localPath: input.existingLocalPath.isEmpty ? nil : input.existingLocalPath,
            downloadUrl: input.path,
            configJson: nil,
            repositoryUrl: repositoryUrl
        )
    }

    /// Ưu tiên `plugin.json` cục bộ nếu tiện ích đã được tải về.
    private static func localMetadata(forLocalPath localPath: String) -> Metadata? {
        guard !localPath.isEmpty else { return nil }
        let localJsonUrl = URL(fileURLWithPath: localPath).appendingPathComponent("plugin.json")
        guard FileManager.default.fileExists(atPath: localJsonUrl.path),
              let jsonData = try? Data(contentsOf: localJsonUrl) else { return nil }
        return parse(jsonData)
    }

    /// Fallback: tải `plugin.json` từ thư mục gốc của file zip trên mạng.
    private static func remoteMetadata(for input: Input) async -> Metadata? {
        guard let zipURL = URL(string: input.path) else { return nil }
        let pluginURL = zipURL.deletingLastPathComponent().appendingPathComponent("plugin.json")
        var request = URLRequest(url: pluginURL)
        request.timeoutInterval = requestTimeout
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            return parse(data)
        } catch {
            AppLogger.shared.log("⚠️ [ExtSync] Lỗi tải/parse plugin.json từ mạng cho \(input.name): \(error.localizedDescription)")
            return nil
        }
    }

    private static func parse(_ data: Data) -> Metadata? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let meta = json["metadata"] as? [String: Any] ?? json
        var result = Metadata()
        result.author = meta["author"] as? String
        result.locale = (meta["locale"] as? String) ?? (meta["language"] as? String)
        result.type = meta["type"] as? String
        if let intVersion = meta["version"] as? Int {
            result.version = intVersion
        } else if let stringVersion = meta["version"] as? String {
            result.version = Int(stringVersion)
        }
        result.source = meta["source"] as? String
        return result
    }
}
