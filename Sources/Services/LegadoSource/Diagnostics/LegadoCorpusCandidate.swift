import Foundation

/// Một nguồn Legado đã cài sẽ được nghiệm thu — bản chụp bất biến, băng qua ranh giới task được.
struct LegadoCorpusCandidate: Sendable, Equatable {
    let packageId: String
    let name: String
    let localPath: String
    let downloadUrl: String
    let configJson: String

    init(extensionRow: Extension) {
        self.packageId = extensionRow.packageId
        self.name = extensionRow.name
        self.localPath = extensionRow.localPath
        self.downloadUrl = extensionRow.downloadUrl
        self.configJson = extensionRow.configJson.isEmpty ? "{}" : extensionRow.configJson
    }

    /// Chọn nguồn theo yêu cầu. Đọc bảng chụp `nonisolated` (không await). Gọi sau khi
    /// `LegadoSourceRepository.isSnapshotReady` — trước đó mọi nguồn Legado bị coi là tắt.
    ///
    /// - `allEnabled`: mọi nguồn `LegadoSourcePolicy.isRunnable` (Legado + loại chạy được + đang bật), xếp theo tên.
    /// - `packageIds`: giữ thứ tự client gửi; id không có trên app / không phải Legado / loại chưa hỗ trợ / đang tắt
    ///   thành kết quả `skipped` có lý do (không vào mẫu số).
    /// `limit` chỉ cắt danh sách sẽ chạy, không cắt danh sách bỏ qua.
    static func select(
        for request: LegadoCorpusRequest
    ) -> (candidates: [LegadoCorpusCandidate], skipped: [LegadoCorpusReport.SourceResult]) {
        var candidates: [LegadoCorpusCandidate] = []
        var skipped: [LegadoCorpusReport.SourceResult] = []

        switch request.selection {
        case .allEnabled:
            candidates = ExtensionLibraryRepository.installedSnapshot()
                .filter { LegadoSourcePolicy.isRunnable($0) }
                .sorted { lhs, rhs in
                    lhs.name == rhs.name ? lhs.packageId < rhs.packageId : lhs.name < rhs.name
                }
                .map { LegadoCorpusCandidate(extensionRow: $0) }
        case .packageIds(let ids):
            for id in ids {
                guard let row = ExtensionLibraryRepository.snapshot(packageId: id) else {
                    skipped.append(.skipped(packageId: id, name: id, reason: "Không có trên app"))
                    continue
                }
                if let reason = skipReason(for: row) {
                    skipped.append(.skipped(packageId: row.packageId, name: row.name, reason: reason))
                    continue
                }
                candidates.append(LegadoCorpusCandidate(extensionRow: row))
            }
        }

        if let limit = request.limit, candidates.count > limit {
            candidates = Array(candidates.prefix(limit))
        }
        return (candidates, skipped)
    }

    private static func skipReason(for row: Extension) -> String? {
        guard let kind = LegadoSourceIdentity.kind(of: row) else {
            return "Không phải nguồn Legado"
        }
        guard LegadoSourcePolicy.isSupportedInCurrentPhase(kind) else {
            return "Loại \(kind.label) chưa hỗ trợ ở bản này"
        }
        guard LegadoSourceRepository.isEnabled(packageId: row.packageId) else {
            return "Nguồn đang tắt"
        }
        return nil
    }

    /// Chờ bảng chụp nguồn Legado sẵn sàng (tối đa ~10 giây): nhờ MainActor nạp nếu chưa nạp.
    static func waitForLegadoSnapshot() async -> Bool {
        if LegadoSourceRepository.isSnapshotReady { return true }
        await MainActor.run {
            LegadoSourceRepository.shared.loadIfNeeded()
        }
        for _ in 0..<50 {
            if LegadoSourceRepository.isSnapshotReady { return true }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        return LegadoSourceRepository.isSnapshotReady
    }
}
