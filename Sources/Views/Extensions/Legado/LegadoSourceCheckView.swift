import SwiftUI

/// Màn **Kiểm tra nguồn** (spec §12.4): chạy `LegadoCorpusRunner` (4 nguồn song song, mỗi nguồn tìm/khám phá → chi
/// tiết → mục lục → chương đầu) trên danh sách nguồn được giao, hiện tiêu đề phạm vi, thanh tiến độ, 3 ô Đạt / Lỗi /
/// Còn lại, chip lọc Tất cả / Lỗi / Đạt, dòng từng nguồn (nút 🐞 ⇒ Gỡ lỗi từng bước), và các hành động trên nguồn lỗi:
/// **Tắt nguồn lỗi**, **Gắn nhóm "Lỗi"**, **Xoá nguồn lỗi** (hỏi xác nhận), **Dừng** khi đang chạy.
///
/// Một lượt tại một thời điểm (bộ chạy dùng chung với Debug server). Gọi thẳng API Swift của bộ chạy (không qua mạng),
/// thăm dò trạng thái mỗi giây. Không tự tạo `NavigationStack` — nơi trình bày bọc (sheet từ menu ⋯) hoặc đẩy trong
/// stack của màn chi tiết. Rời màn (không phải để mở Gỡ lỗi) ⇒ dừng lượt đang chạy.
struct LegadoSourceCheckView: View {
    let packageIds: [String]
    let scopeTitle: String

    private enum Filter: String, CaseIterable, Identifiable {
        case all, failed, passed
        var id: String { rawValue }
        var label: String {
            switch self {
            case .all: return "Tất cả"
            case .failed: return "Lỗi"
            case .passed: return "Đạt"
            }
        }
    }

    static let failedGroupName = "Lỗi"

    @State private var report: LegadoCorpusReport?
    @State private var runId: String?
    @State private var hasStarted = false
    @State private var startError: String?
    @State private var isBusyConflict = false
    @State private var filter: Filter = .all
    @State private var debugPackageId: String?
    @State private var actionMessage: String?
    @State private var showingDeleteConfirm = false
    @State private var isActing = false

    private var isRunning: Bool { report?.state == .running }
    private var results: [LegadoCorpusReport.SourceResult] { report?.sources ?? [] }
    private var failedIds: [String] { results.filter { $0.outcome == .failed }.map(\.packageId) }

    var body: some View {
        VStack(spacing: 10) {
            header
            if let startError {
                startErrorView(startError)
            } else {
                summaryTiles
                filterChips
                resultList
                actionBar
            }
        }
        .padding(.top, 8)
        .navigationTitle("Kiểm tra nguồn")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $debugPackageId) { id in
            LegadoSourceDebugView(packageId: id, sourceName: displayName(for: id))
        }
        .alert("Xoá nguồn lỗi?", isPresented: $showingDeleteConfirm) {
            Button("Huỷ", role: .cancel) {}
            Button("Xoá \(failedIds.count) nguồn", role: .destructive) { deleteFailed() }
        } message: {
            Text("Gỡ các nguồn kiểm tra lỗi khỏi ứng dụng. Kết quả kiểm tra chỉ để tham khảo — nguồn báo lỗi chưa chắc đã hỏng.")
        }
        .task {
            await startIfNeeded()
            await poll()
        }
        .onDisappear {
            // Mở Gỡ lỗi (đẩy màn mới) cũng làm màn này "biến mất" — chỉ dừng khi thật sự rời màn.
            guard debugPackageId == nil, isRunning else { return }
            cancelRun()
        }
    }

    // MARK: - Phần trên

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(scopeTitle)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
            Text("\(packageIds.count) nguồn · từ khoá: checkKeyWord của nguồn, không có thì \"\(LegadoCorpusRequest.fallbackKeyword)\"")
                .font(.caption)
                .foregroundColor(.secondary)
            if let report {
                ProgressView(value: Double(report.completed), total: Double(max(report.totalSources, 1)))
                if isRunning, !report.inFlight.isEmpty {
                    Text("Đang chạy: " + report.inFlight.joined(separator: ", "))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            } else if startError == nil {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
    }

    private var summaryTiles: some View {
        let passed = report?.passed ?? 0
        let failed = (report?.attempted ?? 0) - passed
        let remaining = max(0, (report?.totalSources ?? packageIds.count) - (report?.completed ?? 0))
        return HStack(spacing: 8) {
            tile("Đạt", value: passed, color: .green)
            tile("Lỗi", value: failed, color: .red)
            tile("Còn lại", value: remaining, color: .secondary)
        }
        .padding(.horizontal)
    }

    private func tile(_ title: String, value: Int, color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundColor(color)
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
    }

    private var filterChips: some View {
        HStack(spacing: 8) {
            ForEach(Filter.allCases) { item in
                let isSelected = item == filter
                Button(action: { filter = item }) {
                    Text(item.label)
                        .font(.caption.weight(isSelected ? .semibold : .regular))
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                        .background(isSelected ? Color.accentColor.opacity(0.85) : Color(.secondarySystemBackground))
                        .foregroundColor(isSelected ? .white : .primary)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal)
    }

    // MARK: - Danh sách

    @ViewBuilder
    private var resultList: some View {
        let names = displayNames
        let rows = results.filter { result in
            switch filter {
            case .all: return true
            case .failed: return result.outcome == .failed
            case .passed: return result.outcome == .passed
            }
        }
        if rows.isEmpty {
            VStack {
                Spacer()
                Text(isRunning ? "Đang kiểm tra…" : "Không có nguồn nào ở mục này.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(Array(rows.enumerated()), id: \.offset) { _, result in
                LegadoSourceCheckRow(
                    result: result,
                    displayName: names[result.packageId] ?? result.name,
                    onDebug: { debugPackageId = result.packageId }
                )
            }
            .listStyle(.plain)
        }
    }

    // MARK: - Hành động

    private var actionBar: some View {
        VStack(spacing: 6) {
            if let actionMessage {
                Text(actionMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            HStack(spacing: 8) {
                if isRunning {
                    actionButton("Dừng", systemImage: "stop.fill", tint: .red, action: cancelRun)
                } else {
                    actionButton("Tắt nguồn lỗi", systemImage: "power", tint: .orange, action: disableFailed)
                    actionButton("Gắn nhóm \"\(Self.failedGroupName)\"", systemImage: "tag", tint: .blue, action: tagFailed)
                    actionButton("Xoá nguồn lỗi", systemImage: "trash", tint: .red, action: { showingDeleteConfirm = true })
                }
            }
            .disabled(isActing || (!isRunning && failedIds.isEmpty))
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    private func actionButton(_ title: String, systemImage: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                Text(title)
                    .font(.caption2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .foregroundColor(tint)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private func startErrorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            if isBusyConflict {
                Button("Dừng lượt đang chạy") {
                    Task { _ = await LegadoCorpusRunner.shared.cancel(runId: nil) }
                }
                .buttonStyle(.bordered)
            }
            Spacer()
        }
        .padding()
    }

    /// Tên hiển thị (dịch QT) theo `packageId`.
    private var displayNames: [String: String] {
        var table: [String: String] = [:]
        let wanted = Set(packageIds)
        for summary in LegadoSourceRepository.shared.summaries where wanted.contains(summary.packageId) {
            table[summary.packageId] = summary.displayName
        }
        return table
    }

    private func displayName(for packageId: String) -> String {
        displayNames[packageId] ?? results.first(where: { $0.packageId == packageId })?.name ?? packageId
    }

    // MARK: - Chạy

    private func startIfNeeded() async {
        guard !hasStarted else { return }
        hasStarted = true
        switch LegadoCorpusRequest.make(packageIds: packageIds, allEnabled: nil, keyword: nil, limit: nil) {
        case .failure(let issue):
            startError = issue.message
        case .success(let request):
            do {
                let initial = try await LegadoCorpusRunner.shared.start(request)
                runId = initial.runId
                report = initial
            } catch let error as LegadoCorpusRunner.StartError {
                if case .busy = error {
                    isBusyConflict = true
                    startError = "Đang có một lượt kiểm tra khác (từ màn này hoặc Debug server). Dừng lượt đó rồi mở lại."
                } else {
                    startError = error.message
                }
            } catch {
                startError = error.localizedDescription
            }
        }
    }

    /// Thăm dò mỗi giây tới khi lượt của màn này xong. Task bị huỷ khi màn ẩn — mở lại thì thăm dò tiếp.
    private func poll() async {
        guard let runId else { return }
        while !Task.isCancelled {
            if let current = await LegadoCorpusRunner.shared.status(includeSources: true), current.runId == runId {
                report = current
                if current.state != .running { return }
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }

    private func cancelRun() {
        let id = runId
        Task { _ = await LegadoCorpusRunner.shared.cancel(runId: id) }
    }

    private func disableFailed() {
        let ids = failedIds
        perform { await LegadoSourceCoordinator.shared.setEnabled(false, packageIds: ids) } describe: { "Đã tắt \($0) nguồn lỗi" }
    }

    private func tagFailed() {
        let ids = failedIds
        perform { await LegadoSourceCoordinator.shared.addGroup(Self.failedGroupName, packageIds: ids) } describe: {
            "Đã gắn nhóm \"\(Self.failedGroupName)\" cho \($0) nguồn"
        }
    }

    private func deleteFailed() {
        let ids = failedIds
        perform { await LegadoSourceCoordinator.shared.delete(packageIds: ids) } describe: { "Đã xoá \($0) nguồn lỗi" }
    }

    private func perform(
        _ operation: @escaping @MainActor () async -> Result<Int, LegadoSourceError>,
        describe: @escaping (Int) -> String
    ) {
        guard !isActing else { return }
        isActing = true
        Task { @MainActor in
            let result = await operation()
            isActing = false
            switch result {
            case .success(let count): actionMessage = describe(count)
            case .failure(let error): actionMessage = error.localizedDescription
            }
        }
    }
}
