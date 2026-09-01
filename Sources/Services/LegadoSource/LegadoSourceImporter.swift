import Foundation

/// Nhập nguồn truyện JSON của Legado: từ URL, từ file, hoặc từ chuỗi dán tay.
///
/// Kết quả là danh sách `UpsertExtensionCommand` để View đưa qua `ExtensionTransactionCoordinator` —
/// tầng Service **không** tự chạm `ModelContext` (luật `VIEW_SWIFTDATA_MUTATION` và quy ước ghi
/// SwiftData của repo).
public actor LegadoSourceImporter {
    public static let shared = LegadoSourceImporter()

    private init() {}

    public struct Outcome: Sendable {
        public let commands: [UpsertExtensionCommand]
        public let importedCount: Int
        public let skippedNonText: Int
        public let skippedIncomplete: Int
        /// Cảnh báo theo từng nguồn: tên nguồn → danh sách tính năng chưa hỗ trợ.
        public let warnings: [String: [String]]

        public var totalFound: Int {
            importedCount + skippedNonText + skippedIncomplete
        }
    }

    // MARK: - Nguồn dữ liệu

    public func importFromURL(_ urlString: String) async throws -> Outcome {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme != nil else {
            throw LegadoRuntimeError.invalidSourceJSON("URL không hợp lệ: \(trimmed)")
        }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, _) = try await URLSession.shared.data(for: request)
        return try await importFromData(data)
    }

    public func importFromData(_ data: Data) async throws -> Outcome {
        let sources = LegadoBookSource.parseList(data: data)
        guard !sources.isEmpty else {
            throw LegadoRuntimeError.invalidSourceJSON("không tìm thấy nguồn nào trong tệp")
        }
        return await buildCommands(sources)
    }

    public func importFromText(_ text: String) async throws -> Outcome {
        guard let data = text.data(using: .utf8) else {
            throw LegadoRuntimeError.invalidSourceJSON("không đọc được chuỗi dán vào")
        }
        return try await importFromData(data)
    }

    // MARK: - Dựng command

    private func buildCommands(_ sources: [LegadoBookSource]) async -> Outcome {
        var commands: [UpsertExtensionCommand] = []
        var warnings: [String: [String]] = [:]
        var skippedNonText = 0
        var skippedIncomplete = 0
        var seenPackageIds = Set<String>()

        for source in sources {
            guard source.isTextSource else {
                skippedNonText += 1
                continue
            }
            let missing = source.missingEssentialRules
            guard missing.isEmpty else {
                skippedIncomplete += 1
                continue
            }
            guard !seenPackageIds.contains(source.packageId) else { continue }
            seenPackageIds.insert(source.packageId)

            let localPath: String
            do {
                localPath = try await LegadoSourceStore.shared.write(source)
            } catch {
                AppLogger.shared.log("❌ [LegadoImport] Không ghi được \(source.bookSourceName): \(error.localizedDescription)")
                skippedIncomplete += 1
                continue
            }

            let unsupported = LegadoUnsupportedFeature.scan(source)
            if !unsupported.isEmpty {
                warnings[source.bookSourceName] = unsupported.map(\.rawValue).sorted()
            }

            commands.append(UpsertExtensionCommand(
                packageId: source.packageId,
                name: source.bookSourceName,
                author: source.bookSourceGroup ?? "Legado",
                // Cố định `version = 1` và để `remoteVersion = nil` ⇒ `hasUpdate == false`, nút
                // Cập nhật không hiện. Nguồn Legado cập nhật bằng cách import lại, không có kênh
                // kiểm tra phiên bản.
                version: 1,
                remoteVersion: nil,
                sourceUrl: source.bookSourceUrl,
                iconUrl: nil,
                desc: descriptionText(for: source, unsupported: unsupported),
                type: ExtensionType.legado,
                locale: "zh_CN",
                localPath: localPath,
                downloadUrl: "",
                configJson: "{}",
                repositoryUrl: nil
            ))
        }

        return Outcome(
            commands: commands,
            importedCount: commands.count,
            skippedNonText: skippedNonText,
            skippedIncomplete: skippedIncomplete,
            warnings: warnings
        )
    }

    private func descriptionText(
        for source: LegadoBookSource,
        unsupported: Set<LegadoUnsupportedFeature>
    ) -> String {
        var parts: [String] = []
        if let comment = source.bookSourceComment, !comment.isEmpty {
            parts.append(comment)
        }
        if let group = source.bookSourceGroup, !group.isEmpty {
            parts.append("Nhóm: " + group)
        }
        if !unsupported.isEmpty {
            let names = unsupported.map(\.rawValue).sorted().joined(separator: ", ")
            parts.append("⚠️ Cần tính năng chưa hỗ trợ: " + names)
        }
        return parts.joined(separator: "\n")
    }
}
