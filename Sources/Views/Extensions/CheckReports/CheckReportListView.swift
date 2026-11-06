import SwiftUI

/// Trang "Báo cáo kiểm tra" (1.3.759), đẩy vào từ ngăn kéo … của tab Tiện Ích (ngăn JS mở sẵn loại JS, ngăn Legado mở
/// sẵn loại Legado). Hai chip chọn loại, mỗi báo cáo đã lưu một hàng panel (`CheckReportRow`): chạm ⇒ chi tiết chỉ xem,
/// [Chia sẻ][Xoá] cuối hàng. Ngăn kéo … của trang: Xoá hết theo từng loại (hỏi xác nhận, chừa lượt đang chạy).
///
/// Số liệu ở `CheckReportRepository` (đọc lại mỗi lần vào trang, kéo xuống để làm mới; mỗi lần đọc tự dọn theo luật
/// giữ 20 bản mới nhất mỗi loại). View không đụng đĩa.
struct CheckReportListView: View {
    @State private var kind: CheckReportKind
    @State private var showingMenu = false
    @State private var openedSummary: CheckReportSummary?
    @State private var deleteTarget: DeleteTarget?
    @State private var sharingId: String?
    @State private var shareURL: URL?
    @State private var message: String?

    private enum DeleteTarget: Equatable {
        case one(CheckReportSummary)
        case all(CheckReportKind)
    }

    private var repository: CheckReportRepository { .shared }

    init(initialKind: CheckReportKind) {
        _kind = State(initialValue: initialKind)
    }

    var body: some View {
        let rows = repository.summaries(for: kind)
        List {
            Section {
                kindChips
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                Text(statusLine(count: rows.count))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                if let message {
                    Text(message)
                        .font(.caption)
                        .foregroundColor(.orange)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
            }
            if rows.isEmpty {
                emptyState
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            } else {
                ForEach(rows) { summary in
                    CheckReportRow(
                        summary: summary,
                        isSharing: sharingId == summary.id,
                        onOpen: { openedSummary = summary },
                        onShare: { share(summary) },
                        onDelete: { deleteTarget = .one(summary) }
                    )
                    .bookListPanelRow()
                }
            }
        }
        .listStyle(.plain)
        .backPageTitle("Báo cáo kiểm tra")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showingMenu = true }) {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 36, height: 38)
                }
                .accessibilityLabel("Menu báo cáo kiểm tra")
            }
        }
        .sideDrawerMenu(isPresented: $showingMenu, title: "Báo cáo kiểm tra") { menuItems }
        .navigationDestination(item: $openedSummary) { summary in
            CheckReportDetailView(summary: summary)
        }
        .confirmationDialog(deleteTitle, isPresented: isDeleting, titleVisibility: .visible) {
            Button(isDeletingAll ? "Xoá hết" : "Xoá báo cáo", role: .destructive, action: performDelete)
            Button("Huỷ", role: .cancel) { deleteTarget = nil }
        } message: {
            if isDeletingAll {
                Text("Lượt kiểm tra đang chạy được giữ lại.")
            }
        }
        .sheet(isPresented: isSharing) {
            if let shareURL {
                ShareSheet(activityItems: [shareURL]) { _, _, _, _ in
                    self.shareURL = nil
                }
            }
        }
        .refreshable { await repository.reloadAndWait() }
        .onAppear { repository.reload() }
    }

    // MARK: - Phần trên

    private var kindChips: some View {
        HStack(spacing: 8) {
            ForEach(CheckReportKind.allCases) { item in
                let isSelected = item == kind
                Button(action: { kind = item }) {
                    Text("\(item.title) · \(repository.summaries(for: item).count)")
                        .font(.caption.weight(isSelected ? .semibold : .regular))
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                        .background(isSelected ? Color.accentColor.opacity(0.18) : Color(.secondarySystemBackground))
                        .foregroundColor(isSelected ? .accentColor : .primary)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(isSelected ? Color.accentColor.opacity(0.6) : Color.white.opacity(0.12), lineWidth: 1))
                }
                .buttonStyle(.borderless)
            }
            Spacer(minLength: 0)
        }
    }

    private func statusLine(count: Int) -> String {
        if !repository.hasLoaded { return "Đang đọc báo cáo…" }
        let size = CheckReportFormatter.sizeText(repository.totalBytes(for: kind))
        return "\(count) báo cáo · \(size) · tự giữ \(CheckReportStore.retainedCount) báo cáo mới nhất"
    }

    @ViewBuilder
    private var emptyState: some View {
        if repository.hasLoaded {
            VStack(spacing: 10) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 36))
                    .foregroundColor(.secondary)
                Text(kind == .legado
                     ? "Chưa có báo cáo nào. Chạy \"Kiểm tra nguồn\" ở ngăn kéo … của tab Legado hoặc ở màn chi tiết một nguồn."
                     : "Chưa có báo cáo nào. Chạy \"Kiểm tra tiện ích đang hiện\" ở ngăn kéo … hoặc nút Kiểm tra ở Cấu hình tiện ích.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        } else {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
        }
    }

    // MARK: - Ngăn kéo

    @ViewBuilder
    private var menuItems: some View {
        SideDrawerSectionHeader("Tự giữ \(CheckReportStore.retainedCount) báo cáo mới nhất mỗi loại")
        ForEach(CheckReportKind.allCases) { item in
            let deletable = repository.summaries(for: item).filter(\.isDeletable).count
            SideDrawerActionRow(
                "Xoá hết báo cáo \(item.title)", systemImage: "trash", detail: "\(deletable)", role: .destructive
            ) {
                deleteTarget = .all(item)
            }
            .disabled(deletable == 0)
        }
    }

    // MARK: - Xoá

    private var isDeleting: Binding<Bool> {
        Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } })
    }

    private var deleteTitle: String {
        switch deleteTarget {
        case .one(let summary): return "Xoá báo cáo \(summary.displayTitle)?"
        case .all(let item):
            let count = repository.summaries(for: item).filter(\.isDeletable).count
            return "Xoá hết \(count) báo cáo \(item.title)?"
        case nil: return ""
        }
    }

    private var isDeletingAll: Bool {
        if case .all = deleteTarget { return true }
        return false
    }

    private func performDelete() {
        guard let target = deleteTarget else { return }
        deleteTarget = nil
        Task { @MainActor in
            switch target {
            case .one(let summary):
                if !(await repository.delete(summary)) {
                    message = "Không xoá được báo cáo (lượt kiểm tra còn đang chạy?)."
                }
            case .all(let item):
                let removed = await repository.deleteAll([item])
                message = "Đã xoá \(removed) báo cáo \(item.title)."
            }
        }
    }

    // MARK: - Chia sẻ

    /// Đọc báo cáo + ghi tệp tạm đều qua Services (ngoài main), View chỉ trình bày share sheet.
    private func share(_ summary: CheckReportSummary) {
        guard sharingId == nil else { return }
        sharingId = summary.id
        Task { @MainActor in
            defer { sharingId = nil }
            guard let document = await repository.document(for: summary) else {
                message = "Không đọc được báo cáo này."
                return
            }
            switch await document.writeShareFile() {
            case .success(let url):
                // Cờ còn kẹt từ lần trước (bảng chia sẻ tự đóng mà SwiftUI không biết) ⇒ hạ trước rồi mới trình bày lại.
                if shareURL != nil {
                    shareURL = nil
                    try? await Task.sleep(nanoseconds: 400_000_000)
                }
                shareURL = url
            case .failure(let error):
                message = error.localizedDescription
            }
        }
    }

    private var isSharing: Binding<Bool> {
        Binding(get: { shareURL != nil }, set: { if !$0 { shareURL = nil } })
    }
}
