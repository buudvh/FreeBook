import SwiftUI

/// Màn **Kiểm tra nguồn** (spec §12.4): chạy `LegadoCorpusRunner` (4 nguồn song song, mỗi nguồn tìm/khám phá → chi
/// tiết → mục lục → chương đầu) trên danh sách nguồn được giao, hiện tiêu đề phạm vi, thanh tiến độ, 3 ô Đạt / Lỗi /
/// Còn lại, phần "Lỗi do ai" (ô đếm theo kết luận + chip lọc, `LegadoSourceCheckVerdictPanel`), dòng từng nguồn (nút 🐞
/// ⇒ Gỡ lỗi từng bước), và các hành động trên nguồn lỗi: **Tắt nguồn lỗi**, **Gắn nhóm "Lỗi"**, **Xoá nguồn lỗi** (hỏi
/// xác nhận), **Dừng** khi đang chạy. Nút chia sẻ (toolbar) xuất JSON báo cáo lượt hiện tại (đã redact) qua Services.
///
/// Một lượt tại một thời điểm (bộ chạy dùng chung với Debug server). Gọi thẳng API Swift của bộ chạy (không qua mạng),
/// thăm dò trạng thái mỗi giây. Không tự tạo `NavigationStack` — nơi trình bày bọc (sheet từ menu ⋯) hoặc đẩy trong
/// stack của màn chi tiết. Từ 1.3.697 rời màn (nút ⌄, vuốt xuống, quay lại — không phải để mở Gỡ lỗi) khi lượt còn chạy
/// ⇒ lượt **thu nhỏ** (`MinimizedSourceCheckCoordinator`, dòng "Kiểm tra nguồn" của hub nổi); chỉ nút Dừng mới dừng.
/// `attachRunId` ⇒ màn mở lại từ hub, gắn vào lượt đó thay vì chạy lượt mới.
struct LegadoSourceCheckView: View {
    let packageIds: [String]
    let scopeTitle: String
    /// Gốc của sheet (menu ⋯) ⇒ hiện tiêu đề trái; đẩy trong stack của màn chi tiết ⇒ tiêu đề giữa.
    var isPresentedAsSheet = false
    var attachRunId: String?
    /// Màn trình bày bằng UIKit (mở lại từ hub) tự đóng qua đây thay vì `dismiss` của environment.
    var onClose: (() -> Void)?

    static let failedGroupName = "Lỗi"

    @Environment(\.dismiss) private var dismiss
    @StateObject private var lease = MinimizedSourceCheckCoordinator.ScreenLease()
    @State private var report: LegadoCorpusReport?
    @State private var runId: String?
    @State private var hasStarted = false
    @State private var startError: String?
    @State private var isBusyConflict = false
    @State private var filter: LegadoSourceCheckFilter = .all
    @State private var debugPackageId: String?
    @State private var actionMessage: String?
    @State private var showingDeleteConfirm = false
    @State private var isActing = false
    @State private var shareURL: URL?
    @State private var isPreparingShare = false

    private var isRunning: Bool { report?.state == .running }
    private var results: [LegadoCorpusReport.SourceResult] { report?.sources ?? [] }
    private var failedIds: [String] { results.filter { $0.outcome == .failed }.map(\.packageId) }

    var body: some View {
        VStack(spacing: 10) {
            header
            if let startError {
                SourceCheckStartErrorView(
                    message: startError,
                    onOpenRunning: canOpenMinimizedRun ? openMinimizedRun : nil,
                    onStopRunning: isBusyConflict ? stopOtherRun : nil
                )
            } else {
                summaryTiles
                LegadoSourceCheckVerdictPanel(results: results, filter: $filter)
                resultList
                actionBar
            }
        }
        .padding(.top, 8)
        .pageTitle("Kiểm tra nguồn", style: isPresentedAsSheet ? .leading : .centered)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                SourceCheckHeaderButtons(
                    showsMinimize: isRunning,
                    isShareDisabled: (report?.sources?.isEmpty ?? true) || isPreparingShare,
                    onMinimize: minimize,
                    onShare: shareReport
                )
            }
        }
        .sheet(isPresented: isSharing) {
            if let shareURL {
                ShareSheet(activityItems: [shareURL]) { _, _, _, _ in
                    self.shareURL = nil
                }
            }
        }
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
            // Mở Gỡ lỗi (đẩy màn mới) cũng làm màn này "biến mất" — chỉ tính khi thật sự rời màn. Không xét cờ chia sẻ:
            // bảng chia sẻ không làm màn biến mất, cờ còn kẹt thì lại chặn mất việc thu nhỏ (1.3.702).
            guard debugPackageId == nil else { return }
            MinimizedSourceCheckCoordinator.shared.screenDidClose(.legado, screenId: lease.id)
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
            SourceCheckTile(title: "Đạt", value: passed, color: .green)
            SourceCheckTile(title: "Lỗi", value: failed, color: .red)
            SourceCheckTile(title: "Còn lại", value: remaining, color: .secondary)
        }
        .padding(.horizontal)
    }

    // MARK: - Danh sách

    @ViewBuilder
    private var resultList: some View {
        let names = displayNames
        let rows = results.filter { filter.matches($0) }
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
            List(Array(rows.enumerated()), id: \.offset) { _, result in Group {
                LegadoSourceCheckRow(
                    result: result,
                    displayName: names[result.packageId] ?? result.name,
                    onDebug: { debugPackageId = result.packageId }
                )
            }.glassSheetRows() }
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
                    SourceCheckActionButton("Dừng", systemImage: "stop.fill", tint: .red, action: cancelRun)
                } else {
                    SourceCheckActionButton("Tắt nguồn lỗi", systemImage: "power", tint: .orange, action: disableFailed)
                    SourceCheckActionButton("Gắn nhóm \"\(Self.failedGroupName)\"", systemImage: "tag", tint: .blue, action: tagFailed)
                    SourceCheckActionButton("Xoá nguồn lỗi", systemImage: "trash", tint: .red, action: { showingDeleteConfirm = true })
                }
            }
            .disabled(isActing || (!isRunning && failedIds.isEmpty))
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
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
        if let attachRunId {
            await attach(to: attachRunId)
            return
        }
        switch LegadoCorpusRequest.make(packageIds: packageIds, allEnabled: nil, keyword: nil, limit: nil) {
        case .failure(let issue):
            startError = issue.message
        case .success(let request):
            do {
                let initial = try await LegadoCorpusRunner.shared.start(request, title: scopeTitle)
                runId = initial.runId
                report = initial
                track(initial)
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

    /// Màn mở lại từ hub: không chạy lượt mới, đọc ngay kết quả hiện có của lượt đang thu nhỏ.
    private func attach(to id: String) async {
        guard let current = await LegadoCorpusRunner.shared.status(includeSources: true), current.runId == id else {
            MinimizedSourceCheckCoordinator.shared.discard(.legado, runId: id)
            startError = MinimizedSourceCheckCoordinator.replacedRunMessage
            return
        }
        runId = id
        report = current
        track(current)
    }

    /// Giao lượt cho `MinimizedSourceCheckCoordinator` (màn đang mở). Màn đã đóng trong lúc chờ bộ chạy (task bị huỷ) ⇒
    /// thu nhỏ luôn, kẻo lượt chạy mà không ai theo dõi.
    private func track(_ report: LegadoCorpusReport) {
        let coordinator = MinimizedSourceCheckCoordinator.shared
        coordinator.track(
            .legado, scopeTitle: scopeTitle, progress: .init(report), payload: .legado(packageIds: packageIds), screen: lease
        )
        if Task.isCancelled {
            coordinator.screenDidClose(.legado, screenId: lease.id)
        }
    }

    /// Thăm dò mỗi giây tới khi lượt của màn này xong. Task bị huỷ khi màn ẩn — mở lại thì thăm dò tiếp.
    private func poll() async {
        guard let runId else { return }
        while !Task.isCancelled {
            if let current = await LegadoCorpusRunner.shared.status(includeSources: true), current.runId == runId {
                report = current
                MinimizedSourceCheckCoordinator.shared.update(.legado, progress: .init(current))
                if current.state != .running { return }
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }

    /// Nút ⌄: giao lượt cho hub **trước** rồi mới đóng màn — không trông vào `onDisappear`, máy thật có lúc không gọi
    /// khi sheet đóng (1.3.702).
    private func minimize() {
        MinimizedSourceCheckCoordinator.shared.screenDidClose(.legado, screenId: nil)
        closeScreen()
    }

    private func closeScreen() {
        if let onClose {
            onClose()
        } else {
            dismiss()
        }
    }

    /// Màn báo bận mà lượt kia đang thu nhỏ ⇒ đóng màn này rồi mở lại màn của lượt kia.
    private var canOpenMinimizedRun: Bool {
        isBusyConflict && MinimizedSourceCheckCoordinator.shared.entry(for: .legado)?.isMinimized == true
    }

    private func openMinimizedRun() {
        closeScreen()
        MinimizedSourceCheckCoordinator.shared.reopen(.legado, delay: 600_000_000)
    }

    /// Lượt kia có thể đang thu nhỏ ⇒ thôi theo dõi như nút Dừng, hub không giữ dòng "Đã dừng".
    private func stopOtherRun() {
        MinimizedSourceCheckCoordinator.shared.discard(.legado)
        Task { _ = await LegadoCorpusRunner.shared.cancel(runId: nil) }
    }

    /// Chia sẻ JSON báo cáo lượt hiện tại: Services ghi tệp tạm (ngoài main), View chỉ trình bày share sheet.
    private func shareReport() {
        guard let report, !isPreparingShare else { return }
        isPreparingShare = true
        Task { @MainActor in
            let result = await LegadoCorpusReportShare.write(report)
            switch result {
            case .success(let url):
                // Cờ còn kẹt từ lần trước (bảng chia sẻ tự đóng mà SwiftUI không biết) ⇒ hạ trước, chờ sheet cũ gỡ
                // xong rồi mới trình bày lại — gán thẳng URL mới khi cờ đang `true` thì không có gì hiện ra.
                if shareURL != nil {
                    shareURL = nil
                    try? await Task.sleep(nanoseconds: 400_000_000)
                }
                shareURL = url
            case .failure(let error):
                actionMessage = error.localizedDescription
            }
            isPreparingShare = false
        }
    }

    private var isSharing: Binding<Bool> {
        Binding(get: { shareURL != nil }, set: { if !$0 { shareURL = nil } })
    }

    /// Nút Dừng — lối dừng duy nhất từ 1.3.697: thôi theo dõi rồi huỷ lượt.
    private func cancelRun() {
        let id = runId
        MinimizedSourceCheckCoordinator.shared.discard(.legado, runId: id)
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
