import Foundation

/// Thao tác của màn chi tiết nguồn / kiểm tra hàng loạt / liên kết ngoài — vẫn qua cửa ghi duy nhất
/// `LegadoSourceCoordinator` (View không đụng file): đọc nguồn, lưu JSON đã sửa, gắn nhóm, xuất tệp, biến nguồn,
/// nhập từ liên kết `legado://`. Mọi thao tác file chạy trên `LegadoSourceStore.fileQueue`.
extension LegadoSourceCoordinator {
    /// Kết quả lưu JSON đã sửa.
    enum JSONSaveOutcome: Sendable {
        case saved(LegadoImportSummary)
        /// Trùng khít bản đang lưu — không ghi.
        case unchanged
        /// `bookSourceUrl` đổi ⇒ thành nguồn khác (`packageId` khác). Chưa ghi gì: View hỏi lại rồi gọi
        /// `importEditedAsNew`.
        case sourceURLChanged(newPackageId: String)
        case invalid(LegadoSourceJSONValidator.Issue)
        case failed(String)
    }

    // MARK: - Đọc

    /// `source.json` của nguồn đã cài (bản đang lưu, kể cả khoá lạ).
    func loadSource(packageId: String) async -> Result<LegadoBookSource, LegadoSourceError> {
        let directory = Self.directory(forPackageId: packageId)
        return await Self.runOnFileQueue {
            do {
                let data = try LegadoSourceStore.readSourceData(directory: directory)
                return .success(try LegadoBookSource(data: data))
            } catch let error as LegadoSourceError {
                return .failure(error)
            } catch {
                return .failure(.invalidJSON)
            }
        }
    }

    // MARK: - Sửa JSON

    /// Lưu JSON đã sửa của nguồn `packageId`: kiểm (`LegadoSourceJSONValidator`) → cùng `bookSourceUrl` ⇒ ghi qua
    /// đường nhập sẵn có (ghi `source.json` mới, sinh lại `plugin.json`, `version` + 1, upsert, nạp lại danh sách;
    /// runtime tự bỏ bản nguồn đã đệm vì đệm theo `version`). `lastUpdateTime` = lúc lưu (spec §12.5).
    func saveEditedJSON(_ text: String, packageId: String) async -> JSONSaveOutcome {
        let source: LegadoBookSource
        switch LegadoSourceJSONValidator.validate(text) {
        case .failure(let issue): return .invalid(issue)
        case .success(let parsed): source = parsed
        }
        let newPackageId = LegadoSourceIdentity.packageId(forSourceUrl: source.bookSourceUrl)
        guard newPackageId == packageId else { return .sourceURLChanged(newPackageId: newPackageId) }
        let directory = Self.directory(forPackageId: packageId)
        let stored: Data? = await Self.runOnFileQueue { try? LegadoSourceStore.readSourceData(directory: directory) }
        if let stored, stored == source.rawJSON { return .unchanged }
        return await importEdited(source, origin: "trình sửa JSON")
    }

    /// `bookSourceUrl` đã đổi: nhập như nguồn mới; `replacing` khác `nil` ⇒ nhập xong thì xoá nguồn cũ.
    func importEditedAsNew(_ text: String, replacing oldPackageId: String?) async -> JSONSaveOutcome {
        let source: LegadoBookSource
        switch LegadoSourceJSONValidator.validate(text) {
        case .failure(let issue): return .invalid(issue)
        case .success(let parsed): source = parsed
        }
        let outcome = await importEdited(source, origin: "trình sửa JSON (nguồn mới)")
        guard case .saved = outcome, let oldPackageId else { return outcome }
        if case .failure(let error) = await delete(packageId: oldPackageId) {
            return .failed("Đã nhập nguồn mới nhưng không xoá được nguồn cũ: \(error.localizedDescription)")
        }
        return outcome
    }

    private func importEdited(_ source: LegadoBookSource, origin: String) async -> JSONSaveOutcome {
        guard var object = source.rawObject() else { return .failed("Không đọc lại được JSON đã sửa.") }
        object["lastUpdateTime"] = NSNumber(value: Int64(Date().timeIntervalSince1970 * 1000))
        guard let data = LegadoModelJSON.serialize(object) else { return .failed("Không mã hoá được JSON đã sửa.") }
        switch await importPayloads([data], origin: origin) {
        case .failure(let error):
            return .failed(error.localizedDescription)
        case .success(let summary):
            guard summary.importedCount > 0 else {
                let reasons = summary.skippedLines + summary.writeErrors
                return .failed(reasons.isEmpty ? "Không ghi được nguồn." : reasons.joined(separator: "; "))
            }
            if let indexError = summary.indexError { return .failed("Lỗi lưu danh sách tiện ích: \(indexError)") }
            return .saved(summary)
        }
    }

    // MARK: - Nhóm

    /// Thêm nhóm (vd "Lỗi" sau khi kiểm tra hàng loạt) vào `bookSourceGroup` của các nguồn. Trả số nguồn đã đổi.
    func addGroup(_ group: String, packageIds: [String]) async -> Result<Int, LegadoSourceError> {
        let name = group.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return .failure(.emptyInput) }
        let directories = Array(Set(packageIds)).map(Self.directory(forPackageId:))
        guard !directories.isEmpty else { return .success(0) }
        let outcome: (changed: Int, failed: Int) = await Self.runOnFileQueue {
            var changed = 0
            var failed = 0
            for directory in directories {
                do {
                    if try LegadoSourceStore.addGroup(name, directory: directory) { changed += 1 }
                } catch {
                    failed += 1
                }
            }
            return (changed, failed)
        }
        repository.reload()
        AppLogger.shared.log("🏷️ 📚 [LegadoStore] Gắn nhóm cho \(outcome.changed) nguồn (lỗi \(outcome.failed))")
        guard outcome.failed == 0 else { return .failure(.fileWrite("\(outcome.failed) nguồn")) }
        return .success(outcome.changed)
    }

    // MARK: - Xuất

    /// Ghi tệp `.json` (mảng `source.json` nguyên văn, spec §12.1) vào thư mục tạm để chia sẻ.
    func exportSources(packageIds: [String]) async -> Result<LegadoSourceExportFile, LegadoSourceError> {
        var seen = Set<String>()
        let ids = packageIds.filter { seen.insert($0).inserted }
        guard let firstId = ids.first else { return .failure(.noSourcesFound) }
        let directories = ids.map(Self.directory(forPackageId:))
        let singleName = ids.count == 1 ? repository.summaries.first(where: { $0.packageId == firstId })?.name : nil
        let fileName = LegadoSourceExporter.fileName(singleSourceName: singleName, count: ids.count)
        let result: Result<LegadoSourceExportFile, LegadoSourceError> = await Self.runOnFileQueue {
            do {
                let output = try LegadoSourceExporter.export(directories: directories, fileName: fileName)
                return .success(LegadoSourceExportFile(url: output.url, count: output.count, skipped: output.skipped))
            } catch let error as LegadoSourceError {
                return .failure(error)
            } catch {
                return .failure(.fileWrite(error.localizedDescription))
            }
        }
        if case .success(let file) = result {
            AppLogger.shared.log("📤 📚 [LegadoStore] Xuất \(file.count) nguồn (bỏ qua \(file.skipped))")
        }
        return result
    }

    // MARK: - Biến nguồn

    /// `source.getVariable()` của nguồn. Khoá kho trạng thái = `bookSourceUrl` **nguyên văn** (đúng khoá engine).
    /// Không log giá trị.
    func sourceVariable(sourceKey: String) async -> String {
        await Self.runOnFileQueue { LegadoFileStateStore.shared.sourceVariable(sourceKey: sourceKey) }
    }

    func setSourceVariable(_ value: String, sourceKey: String) async {
        await Self.runOnFileQueue { LegadoFileStateStore.shared.setSourceVariable(value, sourceKey: sourceKey) }
        AppLogger.shared.log("✏️ 📚 [LegadoStore] Đã lưu biến nguồn (\(value.count) ký tự)")
    }

    // MARK: - Liên kết ngoài

    /// Nhập từ `src` của liên kết `legado://…/importonline` (đã được người dùng xác nhận): chỉ http/https, tối đa
    /// 20 MB, rồi đúng đường "Nhập nguồn từ URL".
    func importFromLink(_ urlString: String) async -> Result<LegadoImportSummary, LegadoSourceError> {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard LegadoSourceLink.isHTTPURL(trimmed) else { return .failure(.invalidURL(trimmed)) }
        do {
            let data = try await LegadoSourceImporter.download(trimmed, maxBytes: LegadoSourceLink.maxDownloadBytes)
            return await importPayloads([data], origin: "liên kết")
        } catch let error as LegadoSourceError {
            return .failure(error)
        } catch {
            return .failure(.network(error.localizedDescription))
        }
    }
}
