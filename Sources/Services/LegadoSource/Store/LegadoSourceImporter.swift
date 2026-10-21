import Foundation

/// Nhập nguồn Legado: đọc dữ liệu (tệp / URL / chuỗi), phân loại từng nguồn, ghi thư mục, dựng `UpsertExtensionCommand`.
///
/// **Nonisolated**: `importBatch` chạy trên `LegadoSourceStore.fileQueue` (parse + ghi vài nghìn thư mục không bao
/// giờ chạm main). Main chỉ nhận `Outcome` rồi gửi coordinator **một** lời gọi `upsertExtensions(commands:)`.
///
/// Luật (spec §1.1, §1.6, §1.8, §1.9 + plan đã duyệt):
/// - Dữ liệu: mảng / object đơn / chuỗi JSON bị escape (tối đa 2 lớp) / BOM / JSON lỏng.
/// - Bỏ trùng theo `bookSourceUrl` đã trim trong cùng lượt, giữ bản gặp trước.
/// - Loại 0 → chữ, 2 → tranh, 4 → video; 1 (audio), 3 (tệp) và số lạ → bỏ qua kèm lý do. Vắng / không parse được → 0.
/// - Nguồn chữ phải đạt rule tối thiểu (bản nới §1.9); tranh/video chỉ cần URL + tên (chưa chạy ở đợt 1).
/// - Nhập lại cùng khoá = cập nhật: ghi đè nội dung (kể cả `enabled` theo tệp), `version` của `plugin.json` + 1.
///   Bytes trùng khít ⇒ "giống hệt", không ghi lại.
public enum LegadoSourceImporter {
    struct Outcome: Sendable {
        var summary = LegadoImportSummary()
        var commands: [UpsertExtensionCommand] = []
    }

    static let maxDownloadBytes = 64 * 1024 * 1024
    static let downloadTimeout: TimeInterval = 60

    // MARK: - Đọc dữ liệu

    /// Các phần tử cấp cao nhất: mảng ⇒ từng phần tử; object ⇒ một phần tử. Sau khi bóc chuỗi escape.
    public static func topLevelElements(from data: Data) throws -> [Any] {
        guard !data.isEmpty else { throw LegadoSourceError.emptyInput }
        let parsed = LegadoModelJSON.parseDocument(data: data)
        if let array = parsed as? [Any] { return array }
        if let object = parsed as? [String: Any] { return [object] }
        throw LegadoSourceError.invalidJSON
    }

    /// Đọc các tệp người dùng chọn (picker mở dạng bản sao nên không cần security scope).
    static func readFiles(_ urls: [URL]) throws -> [Data] {
        try urls.map { (url: URL) throws -> Data in
            do {
                return try Data(contentsOf: url)
            } catch {
                throw LegadoSourceError.fileRead("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
    }

    /// Tải nội dung URL (http/https) bằng `URLSession` — không chặn main.
    static func download(_ urlString: String) async throws -> Data {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) ?? trimmed
        guard let url = URL(string: trimmed) ?? URL(string: encoded),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            throw LegadoSourceError.invalidURL(trimmed)
        }
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: downloadTimeout)
        let fetched: (Data, URLResponse)
        do {
            fetched = try await URLSession.shared.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw LegadoSourceError.network(error.localizedDescription)
        }
        let (data, response) = fetched
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw LegadoSourceError.httpStatus(http.statusCode)
        }
        guard !data.isEmpty else { throw LegadoSourceError.emptyInput }
        guard data.count <= maxDownloadBytes else { throw LegadoSourceError.responseTooLarge }
        return data
    }

    // MARK: - Nhập

    /// Phân loại + ghi file cho cả lô. Chạy trên `fileQueue`. Không payload nào đọc được ⇒ `.invalidJSON`.
    static func importBatch(_ payloads: [Data]) -> Result<Outcome, LegadoSourceError> {
        var elements: [Any] = []
        var parsedAny = false
        for data in payloads {
            guard let parsed = try? topLevelElements(from: data) else { continue }
            parsedAny = true
            elements.append(contentsOf: parsed)
        }
        guard parsedAny else { return .failure(.invalidJSON) }
        guard !elements.isEmpty else { return .failure(.noSourcesFound) }

        var existing: [String: Extension] = [:]
        for ext in ExtensionLibraryRepository.installedSnapshot() { existing[ext.packageId] = ext }

        var outcome = Outcome()
        var seenKeys = Set<String>()
        for element in elements {
            guard let object = element as? [String: Any] else {
                outcome.summary.skip(.notAnObject)
                continue
            }
            var source = LegadoBookSource(jsonObject: object, rawJSON: Data())
            if let reason = skipReason(for: source, object: object) {
                outcome.summary.skip(reason)
                continue
            }
            let key = LegadoSourceIdentity.normalizedSourceKey(source.bookSourceUrl)
            guard seenKeys.insert(key).inserted else {
                outcome.summary.skip(.duplicateInFile)
                continue
            }
            let packageId = LegadoSourceIdentity.packageId(forSourceUrl: key)
            let record = existing[packageId]
            if let record, !LegadoSourceIdentity.isLegado(record) {
                outcome.summary.skip(.conflictsWithExtension)
                continue
            }
            guard let sourceJSON = LegadoModelJSON.serialize(object) else {
                outcome.summary.skip(.writeFailed)
                continue
            }
            source.rawJSON = sourceJSON
            store(source, sourceJSON: sourceJSON, packageId: packageId, record: record, into: &outcome)
        }
        return .success(outcome)
    }

    /// `nil` = nhận. Thứ tự kiểm: URL (kèm nhận diện định dạng cũ) → tên → loại → rule tối thiểu (chỉ nguồn chữ).
    static func skipReason(for source: LegadoBookSource, object: [String: Any]) -> LegadoImportSkipReason? {
        if source.trimmedSourceUrl.isEmpty {
            let looksLegacy = object.keys.contains { $0.hasPrefix("rule") && $0.hasSuffix("Url") }
            return looksLegacy ? .legacyFormat : .missingSourceUrl
        }
        if source.bookSourceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .missingName }
        switch source.bookSourceType {
        case 0:
            return source.meetsMinimalRules ? nil : .missingMinimalRules
        case 2, 4:
            return nil
        case 1:
            return .audio
        case 3:
            return .downloadFile
        default:
            return .unknownType
        }
    }

    private static func store(
        _ source: LegadoBookSource,
        sourceJSON: Data,
        packageId: String,
        record: Extension?,
        into outcome: inout Outcome
    ) {
        let directory = LegadoSourceStore.directoryURL(packageId: packageId)
        let oldData = try? LegadoSourceStore.readSourceData(directory: directory)
        let manifestVersion = LegadoSourceStore.manifestVersion(directory: directory)

        if let oldData, oldData == sourceJSON, let manifestVersion {
            outcome.summary.unchanged += 1
            // File đủ mà index mất bản ghi (vd index hỏng) ⇒ vẫn gửi command để bản ghi quay lại.
            if record == nil,
               let command = LegadoSourceStore.makeCommand(
                source: source, packageId: packageId, version: manifestVersion, directory: directory
               ) {
                outcome.commands.append(command)
            }
            return
        }

        let isUpdate = oldData != nil || record != nil
        let version = max(manifestVersion ?? 0, record?.version ?? 0) + 1
        do {
            try LegadoSourceStore.writeSource(sourceJSON: sourceJSON, source: source, packageId: packageId, version: version)
        } catch {
            outcome.summary.skip(.writeFailed)
            outcome.summary.writeErrors.append("\(source.bookSourceName): \(error.localizedDescription)")
            return
        }
        guard let command = LegadoSourceStore.makeCommand(
            source: source, packageId: packageId, version: version, directory: directory
        ) else { return }
        outcome.commands.append(command)
        if isUpdate {
            outcome.summary.updated += 1
        } else {
            outcome.summary.added += 1
        }
    }
}
