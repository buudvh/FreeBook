import Foundation

/// Cửa ghi **duy nhất** cho nguồn Legado từ UI: nhập (tệp / URL / chuỗi), bật/tắt (một hoặc hàng loạt), xoá một,
/// xoá tất cả. View không đụng file — chỉ gọi các hàm ở đây và hiện `Result`.
///
/// Luật:
/// - **File trước, bản ghi sau**: ghi/xoá thư mục trên `LegadoSourceStore.fileQueue`, xong mới gọi
///   `ExtensionTransactionCoordinator` (một lời gọi cho cả lô), rồi nạp lại `LegadoSourceRepository`.
/// - Mọi thao tác file đi qua cùng một hàng đợi tuần tự ⇒ bấm bật/tắt liên tiếp được ghi đúng thứ tự; kết quả về main
///   bằng `DispatchQueue.main.async` từ chính hàng đợi đó ⇒ áp đúng thứ tự với các lượt nạp.
/// - Không toast từ đây (Services): trả `Result` / `LegadoImportSummary` cho View.
@MainActor
public final class LegadoSourceCoordinator {
    public static let shared = LegadoSourceCoordinator()

    var repository: LegadoSourceRepository { LegadoSourceRepository.shared }

    private init() {}

    // MARK: - Nhập

    /// Tệp `.json` / `.txt` người dùng chọn (nhiều tệp được gộp làm một lượt).
    public func importFiles(_ urls: [URL]) async -> Result<LegadoImportSummary, LegadoSourceError> {
        guard !urls.isEmpty else { return .failure(.emptyInput) }
        let read: Result<[Data], LegadoSourceError> = await Self.runOnFileQueue {
            do {
                let payloads = try LegadoSourceImporter.readFiles(urls)
                return .success(payloads)
            } catch let error as LegadoSourceError {
                return .failure(error)
            } catch {
                return .failure(.fileRead(error.localizedDescription))
            }
        }
        switch read {
        case .success(let payloads): return await importPayloads(payloads, origin: "tệp")
        case .failure(let error): return .failure(error)
        }
    }

    /// Tải URL (mảng nguồn hoặc một nguồn) rồi nhập.
    public func importFromURL(_ urlString: String) async -> Result<LegadoImportSummary, LegadoSourceError> {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.emptyInput) }
        do {
            let data = try await LegadoSourceImporter.download(trimmed)
            return await importPayloads([data], origin: "URL")
        } catch let error as LegadoSourceError {
            return .failure(error)
        } catch {
            return .failure(.network(error.localizedDescription))
        }
    }

    /// JSON dán từ bộ nhớ tạm.
    public func importText(_ text: String) async -> Result<LegadoImportSummary, LegadoSourceError> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.emptyInput) }
        return await importPayloads([Data(trimmed.utf8)], origin: "bộ nhớ tạm")
    }

    func importPayloads(_ payloads: [Data], origin: String) async -> Result<LegadoImportSummary, LegadoSourceError> {
        let started = Date()
        let batch = await Self.runOnFileQueue { LegadoSourceImporter.importBatch(payloads) }
        guard case .success(var outcome) = batch else {
            if case .failure(let error) = batch {
                AppLogger.shared.log("❌ 📚 [LegadoImport] Nhập từ \(origin) thất bại: \(error.localizedDescription)")
                return .failure(error)
            }
            return .failure(.invalidJSON)
        }
        let written = Date()
        if !outcome.commands.isEmpty,
           case .failure(let error) = ExtensionTransactionCoordinator.shared.upsertExtensions(commands: outcome.commands) {
            outcome.summary.indexError = error.localizedDescription
        }
        repository.reload()

        let summary = outcome.summary
        let parseWrite = String(format: "%.2f", written.timeIntervalSince(started))
        let indexTime = String(format: "%.2f", Date().timeIntervalSince(written))
        AppLogger.shared.log("ℹ️ 📚 [LegadoImport] Từ \(origin): mới \(summary.added), cập nhật \(summary.updated), giống hệt \(summary.unchanged), bỏ qua \(summary.skippedCount) [\(summary.skippedLines.joined(separator: "; "))] — parse+ghi \(parseWrite)s, index \(indexTime)s")
        if !summary.writeErrors.isEmpty || summary.indexError != nil {
            AppLogger.shared.log("❌ 📚 [LegadoImport] Lỗi ghi \(summary.writeErrors.count) nguồn; index: \(summary.indexError ?? "ok")")
        }
        return .success(summary)
    }

    // MARK: - Bật / tắt

    /// Bật/tắt một hoặc nhiều nguồn: vẽ ngay, vá `source.json` trên nền, UI cập nhật một lần. Trả số nguồn đã đổi.
    public func setEnabled(_ enabled: Bool, packageIds: [String]) async -> Result<Int, LegadoSourceError> {
        var seen = Set<String>()
        let current = Dictionary(repository.summaries.map { ($0.packageId, $0.isEnabled) }, uniquingKeysWith: { first, _ in first })
        let targets = packageIds.filter { id in
            guard seen.insert(id).inserted, let isEnabled = current[id] else { return false }
            return isEnabled != enabled
        }
        guard !targets.isEmpty else { return .success(0) }
        let directories = targets.map(Self.directory(forPackageId:))
        let token = repository.beginEnabledChange(targets, enabled: enabled)
        let failed: [String] = await withCheckedContinuation { continuation in
            Self.enqueuePatch(enabled: enabled, packageIds: targets, directories: directories, token: token) { failures in
                continuation.resume(returning: failures)
            }
        }
        guard failed.isEmpty else {
            AppLogger.shared.log("❌ 📚 [LegadoStore] Không vá được enabled của \(failed.count)/\(targets.count) nguồn")
            return .failure(.fileWrite("\(failed.count) nguồn"))
        }
        return .success(targets.count)
    }

    nonisolated private static func enqueuePatch(
        enabled: Bool,
        packageIds: [String],
        directories: [URL],
        token: Int,
        completion: @escaping @Sendable ([String]) -> Void
    ) {
        LegadoSourceStore.fileQueue.async {
            var failures: [String] = []
            for (id, directory) in zip(packageIds, directories) {
                do {
                    try LegadoSourceStore.setEnabled(enabled, directory: directory)
                } catch {
                    failures.append(id)
                }
            }
            let failedList = failures
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    LegadoSourceRepository.shared.finishEnabledChange(
                        packageIds, enabled: enabled, token: token, failed: Set(failedList)
                    )
                }
                completion(failedList)
            }
        }
    }

    // MARK: - Xoá

    /// Xoá một nguồn: ẩn ngay, xoá thư mục trên nền, rồi xoá bản ghi.
    public func delete(packageId: String) async -> Result<Void, LegadoSourceError> {
        switch await deleteSources([packageId]) {
        case .success: return .success(())
        case .failure(let error): return .failure(error)
        }
    }

    /// Xoá nhiều nguồn (kiểm tra hàng loạt: "Xoá nguồn lỗi"). Trả số nguồn đã xoá.
    public func delete(packageIds: [String]) async -> Result<Int, LegadoSourceError> {
        let ids = Array(Set(packageIds))
        guard !ids.isEmpty else { return .success(0) }
        return await deleteSources(ids)
    }

    /// Xoá **mọi** bản ghi Legado trong kho tiện ích (kể cả nguồn chưa nạp vào danh sách). Trả số nguồn đã xoá.
    public func deleteAll() async -> Result<Int, LegadoSourceError> {
        let ids = LegadoSourcePolicy.onlyLegado(ExtensionLibraryRepository.shared.installed).map(\.packageId)
        guard !ids.isEmpty else { return .success(0) }
        return await deleteSources(ids)
    }

    func deleteSources(_ packageIds: [String]) async -> Result<Int, LegadoSourceError> {
        let directories = packageIds.map(Self.directory(forPackageId:))
        // Khoá đăng nhập của engine là `bookSourceUrl` — đọc trước khi thư mục và bản tóm tắt biến mất.
        var loginKeys: [String: String] = [:]
        for id in packageIds {
            if let url = LegadoSourceRepository.summarySnapshot(packageId: id)?.bookSourceUrl, !url.isEmpty {
                loginKeys[id] = url
            }
        }
        let token = repository.beginRemoval(packageIds)
        let failed: [String] = await Self.runOnFileQueue {
            var failures: [String] = []
            for (id, directory) in zip(packageIds, directories) {
                do {
                    try LegadoSourceStore.removeDirectory(directory)
                } catch {
                    failures.append(id)
                }
            }
            return failures
        }
        let failedSet = Set(failed)
        let removed = packageIds.filter { !failedSet.contains($0) }
        var indexError: String?
        if !removed.isEmpty,
           case .failure(let error) = ExtensionTransactionCoordinator.shared.deleteExtensions(packageIds: removed) {
            indexError = error.localizedDescription
        }
        repository.finishRemoval(packageIds, token: token)
        repository.reload()
        // Xoá nguồn ⇒ xoá luôn thông tin đăng nhập trong Keychain của nguồn đó.
        for id in removed {
            if let key = loginKeys[id] { await LegadoLoginService.forget(sourceKey: key) }
        }
        AppLogger.shared.log("🧹 📚 [LegadoStore] Đã xoá \(removed.count)/\(packageIds.count) nguồn Legado")
        if let indexError { return .failure(.index(indexError)) }
        guard failed.isEmpty else {
            AppLogger.shared.log("❌ 📚 [LegadoStore] Không xoá được thư mục của \(failed.count) nguồn")
            return .failure(.fileWrite("không xoá được \(failed.count) thư mục"))
        }
        return .success(removed.count)
    }

    // MARK: - Helpers

    /// Thư mục của bản ghi trong kho tiện ích; dự phòng `extensions/<packageId>/`.
    nonisolated static func directory(forPackageId packageId: String) -> URL {
        if let ext = ExtensionLibraryRepository.snapshot(packageId: packageId), !ext.localPath.isEmpty {
            return URL(fileURLWithPath: ext.localPath, isDirectory: true)
        }
        return LegadoSourceStore.directoryURL(packageId: packageId)
    }

    /// Chạy `work` trên `fileQueue` (tuần tự với mọi thao tác file khác) và chờ kết quả.
    nonisolated static func runOnFileQueue<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            LegadoSourceStore.fileQueue.async {
                continuation.resume(returning: work())
            }
        }
    }
}
