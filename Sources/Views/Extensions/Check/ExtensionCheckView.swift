import SwiftUI

/// Màn **Kiểm tra tiện ích** (tiện ích JS): chạy `ExtensionCheckRunner` trên các tiện ích được giao, thăm dò mỗi giây.
///
/// - **Một tiện ích** (nút "Kiểm tra" ở Cấu hình tiện ích, đẩy trong stack của màn đó): kết quả từng script ngay tại
///   màn (`ExtensionCheckDetailContent`), nút Chạy lại; "Mở link lỗi" ⇒ đóng trình duyệt thì chạy lại tiện ích.
/// - **Hàng loạt** (menu ⋯ tab Tất cả tiện ích, sheet): ô Đạt đủ / Có lỗi / Còn lại, chip lọc, mỗi tiện ích một dòng
///   (`ExtensionCheckBatchRow`) — chạm ⇒ đẩy `ExtensionCheckResultScreen`; nút Chạy lại tất cả và **Gỡ tiện ích lỗi**
///   (hỏi xác nhận, qua `ExtensionTransactionCoordinator`).
///
/// Nút chia sẻ (toolbar) xuất JSON báo cáo đã redact qua Services. Một lượt tại một thời điểm. Không tự tạo
/// `NavigationStack`. Rời màn (không phải để mở màn con / chia sẻ / trình duyệt) ⇒ dừng lượt đang chạy.
struct ExtensionCheckView: View {
    /// Đích của sheet hàng loạt.
    struct Route: Identifiable {
        let id = UUID()
        let targets: [ExtensionCheckRunner.Target]
        let scopeTitle: String
    }

    let targets: [ExtensionCheckRunner.Target]
    let scopeTitle: String

    @State private var report: ExtensionCheckReport?
    @State private var hasStarted = false
    @State private var startError: String?
    @State private var isBusyConflict = false
    @State private var pollGeneration = 0
    @State private var filter: ExtensionCheckFilter = .all
    @State private var openedPackageId: String?
    @State private var openingLink: SourceErrorLink?
    @State private var actionMessage: String?
    @State private var showingUninstallConfirm = false
    @State private var removedIds: Set<String> = []
    @State private var shareURL: URL?
    @State private var isPreparingShare = false

    private var isSingle: Bool { targets.count == 1 }
    private var isRunning: Bool { report?.state == .running }

    /// Tiện ích có lỗi (xong, chưa gỡ) — đích của "Gỡ tiện ích lỗi".
    private var failedIds: [String] {
        (report?.results ?? [])
            .filter { $0.state == .finished && $0.hasProblem && !removedIds.contains($0.packageId) }
            .map(\.packageId)
    }

    var body: some View {
        VStack(spacing: 10) {
            header
            if let startError {
                startErrorView(startError)
            } else if isSingle {
                ExtensionCheckDetailContent(result: report?.results.first, openingLink: $openingLink)
            } else {
                batchContent
            }
            actionBar
        }
        .padding(.top, 8)
        .navigationTitle("Kiểm tra tiện ích")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: shareReport) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .disabled((report?.results.isEmpty ?? true) || isPreparingShare)
                .accessibilityLabel("Chia sẻ báo cáo kiểm tra")
            }
        }
        .sheet(isPresented: isSharing) {
            if let shareURL {
                ShareSheet(activityItems: [shareURL]) { _, _, _, _ in
                    self.shareURL = nil
                }
            }
        }
        .navigationDestination(item: $openedPackageId) { id in
            ExtensionCheckResultScreen(packageId: id, name: targets.first { $0.packageId == id }?.name ?? id)
        }
        .alert("Gỡ tiện ích lỗi?", isPresented: $showingUninstallConfirm) {
            Button("Huỷ", role: .cancel) {}
            Button("Gỡ \(failedIds.count) tiện ích", role: .destructive) { uninstallFailed() }
        } message: {
            Text("Gỡ các tiện ích kiểm tra có lỗi khỏi ứng dụng. Kết quả chỉ để tham khảo — tiện ích báo lỗi chưa chắc đã hỏng (web chặn tạm thời, cần đăng nhập…).")
        }
        .errorLinkBrowser(link: $openingLink, packageId: targets.first?.packageId, onRetry: retrySingle)
        .task(id: pollGeneration) {
            await startIfNeeded()
            await poll()
        }
        .onDisappear {
            // Đẩy màn con / chia sẻ / mở trình duyệt cũng làm màn này "biến mất" — chỉ dừng khi thật sự rời màn.
            guard openedPackageId == nil, shareURL == nil, openingLink == nil, isRunning else { return }
            cancelRun()
        }
    }

    // MARK: - Phần trên

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(scopeTitle)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
            Text(subtitle)
                .font(.caption)
                .foregroundColor(.secondary)
            if let progress {
                ProgressView(value: progress.done, total: max(progress.total, 1))
            } else if startError == nil {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
    }

    private var subtitle: String {
        if isSingle {
            let result = report?.results.first
            let scripts = result.map { "\($0.scripts.count) script" } ?? "Đang đọc plugin.json"
            if result?.kind == .tts {
                return "\(scripts) · chạy thử voice, tts chỉ kiểm tĩnh"
            }
            return "\(scripts) · tìm thử: tối đa \(ExtensionCheckProbe.maxHistoryKeywords) từ gần nhất trong lịch sử, không ra thì tên truyện từ trang chủ"
        }
        return "\(targets.count) tiện ích đã cài · chạy \(ExtensionCheckRunner.maxParallelExtensions) tiện ích cùng lúc"
    }

    /// Một tiện ích: số dòng đã xong / tổng dòng; hàng loạt: số tiện ích đã xong / tổng.
    private var progress: (done: Double, total: Double)? {
        guard let report else { return nil }
        if isSingle {
            guard let scripts = report.results.first?.scripts, !scripts.isEmpty else { return nil }
            let done = scripts.filter { $0.outcome != .pending && $0.outcome != .running }.count
            return (Double(done), Double(scripts.count))
        }
        return (Double(report.completed), Double(report.totalExtensions))
    }

    // MARK: - Hàng loạt

    private var batchContent: some View {
        let results = (report?.results ?? []).filter { !removedIds.contains($0.packageId) }
        let remaining = max(0, (report?.totalExtensions ?? targets.count) - (report?.completed ?? 0))
        let rows = results.filter { filter.matches($0) }
        return VStack(spacing: 10) {
            HStack(spacing: 8) {
                tile("Đạt đủ", value: report?.fullyPassed ?? 0, color: .green)
                tile("Có lỗi", value: report?.withProblems ?? 0, color: .red)
                tile("Còn lại", value: remaining, color: .secondary)
            }
            .padding(.horizontal)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ExtensionCheckFilter.allCases) { item in
                        filterChip(item)
                    }
                }
                .padding(.horizontal)
            }
            if rows.isEmpty {
                VStack {
                    Spacer()
                    Text(isRunning ? "Đang kiểm tra…" : "Không có tiện ích nào ở mục này.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(rows) { result in
                    Button(action: { openedPackageId = result.packageId }) {
                        ExtensionCheckBatchRow(result: result)
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
            }
        }
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

    /// Chip chọn theo kiểu `ExtensionKindFilterBar` (app đặt `.tint(.white)` ⇒ màu nhấn là trắng, chỉ dùng dạng mờ).
    private func filterChip(_ item: ExtensionCheckFilter) -> some View {
        let isSelected = item == filter
        return Button(action: { filter = item }) {
            Text(item.label)
                .font(.caption.weight(isSelected ? .semibold : .regular))
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(isSelected ? Color.accentColor.opacity(0.18) : Color(.secondarySystemBackground))
                .foregroundColor(isSelected ? .accentColor : .primary)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(isSelected ? Color.accentColor.opacity(0.6) : Color.white.opacity(0.12), lineWidth: 1))
        }
        .buttonStyle(.plain)
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
                } else if isSingle {
                    actionButton("Chạy lại", systemImage: "arrow.clockwise", tint: .blue, action: retrySingle)
                } else {
                    actionButton("Chạy lại tất cả", systemImage: "arrow.clockwise", tint: .blue, action: restartAll)
                    actionButton("Gỡ tiện ích lỗi", systemImage: "trash", tint: .red, action: { showingUninstallConfirm = true })
                        .disabled(failedIds.isEmpty)
                }
            }
            .disabled(report == nil && startError == nil)
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
                    Task { await ExtensionCheckRunner.shared.cancel(runId: nil) }
                }
                .buttonStyle(.bordered)
            }
            Spacer()
        }
        .padding()
    }

    // MARK: - Chạy

    private func startIfNeeded() async {
        guard !hasStarted else { return }
        hasStarted = true
        await begin { try await ExtensionCheckRunner.shared.start(targets) }
    }

    /// Gọi lệnh của runner; lỗi bận ⇒ hiện nút dừng lượt kia.
    private func begin(_ command: () async throws -> ExtensionCheckReport) async {
        do {
            report = try await command()
            startError = nil
            isBusyConflict = false
            actionMessage = nil
        } catch let error as ExtensionCheckRunner.StartError {
            if case .busy = error { isBusyConflict = true }
            if report == nil {
                startError = error.message
            } else {
                actionMessage = error.message
            }
        } catch {
            startError = error.localizedDescription
        }
    }

    /// Thăm dò mỗi giây tới khi lượt xong. Task bị huỷ khi màn ẩn — mở lại thì thăm dò tiếp.
    private func poll() async {
        while !Task.isCancelled {
            guard let runId = report?.runId else { return }
            if let current = await ExtensionCheckRunner.shared.status(), current.runId == runId {
                report = current
                if current.state != .running { return }
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }

    private func retrySingle() {
        guard let packageId = targets.first?.packageId else { return }
        Task { @MainActor in
            await begin { try await ExtensionCheckRunner.shared.retry(packageId: packageId) }
            pollGeneration += 1
        }
    }

    private func restartAll() {
        let remaining = targets.filter { !removedIds.contains($0.packageId) }
        Task { @MainActor in
            await begin { try await ExtensionCheckRunner.shared.start(remaining) }
            pollGeneration += 1
        }
    }

    private func cancelRun() {
        let runId = report?.runId
        Task { await ExtensionCheckRunner.shared.cancel(runId: runId) }
    }

    /// Bỏ qua tiện ích đang là giọng đọc TTS — cùng luật chặn của nút Gỡ ở Cấu hình tiện ích (`requestUninstall`).
    @MainActor
    private func uninstallFailed() {
        var removed = 0
        var errors: [String] = []
        for packageId in failedIds {
            if TTSManager.shared.tool == packageId {
                errors.append("tiện ích đang dùng làm giọng đọc, chọn giọng khác trước khi gỡ")
                continue
            }
            switch ExtensionTransactionCoordinator.shared.uninstallExtension(packageId: packageId) {
            case .success:
                removedIds.insert(packageId)
                removed += 1
            case .failure(let error):
                errors.append(error.localizedDescription)
            }
        }
        AppLogger.shared.log("🧹 [ExtCheck] Gỡ \(removed) tiện ích lỗi sau kiểm tra")
        actionMessage = errors.isEmpty ? "Đã gỡ \(removed) tiện ích" : "Đã gỡ \(removed) tiện ích, lỗi: \(errors.first ?? "")"
    }

    // MARK: - Chia sẻ

    /// Services ghi tệp tạm (ngoài main), View chỉ trình bày share sheet.
    private func shareReport() {
        guard let report, !isPreparingShare else { return }
        isPreparingShare = true
        Task { @MainActor in
            switch await ExtensionCheckReportShare.write(report) {
            case .success(let url):
                // Cờ còn kẹt từ lần trước (bảng chia sẻ tự đóng mà SwiftUI không biết) ⇒ hạ trước rồi mới trình bày lại.
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
}
