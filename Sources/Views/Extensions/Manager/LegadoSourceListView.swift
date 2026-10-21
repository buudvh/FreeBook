import SwiftUI

/// Nội dung tab "Nguồn Legado" của màn Kho Tiện Ích: ô tìm, hàng chip nhóm (có số đếm), dòng "Đang bật x/y" và danh
/// sách nguồn. Mọi thao tác ghi đi qua `LegadoSourceCoordinator`; menu ⋯ (nhập, bật/tắt hàng loạt, xoá tất cả) nằm ở
/// toolbar của `RepositoryManagerView` và dùng chung `state`.
///
/// Danh sách có thể vài nghìn dòng: `List` lười, lọc một lần mỗi lượt vẽ trên `searchKey` đã tính sẵn.
struct LegadoSourceListView: View {
    @Binding var state: LegadoSourceTabState

    private var repository: LegadoSourceRepository { LegadoSourceRepository.shared }

    var body: some View {
        let all = repository.summaries
        let visible = state.visibleSummaries(all)

        VStack(spacing: 8) {
            searchField
            groupChips(total: all.count)
            statusLine(visible: visible)
            Divider()
            content(all: all, visible: visible)
        }
        .padding(.top, 6)
        .background(Color(.systemGroupedBackground).opacity(0.3))
    }

    // MARK: - Ô tìm

    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField("Tìm nguồn Legado", text: $state.query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !state.query.isEmpty {
                Button(action: { state.query = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Xoá ô tìm")
            }
        }
        .padding(8)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(10)
        .padding(.horizontal)
    }

    // MARK: - Chip nhóm

    private func groupChips(total: Int) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                groupChip(title: "Tất cả", count: total, filter: .all)
                ForEach(repository.groupCounts) { entry in
                    groupChip(title: entry.translatedGroup, count: entry.count, filter: .group(entry.group))
                }
                if repository.ungroupedCount > 0 {
                    groupChip(title: "Chưa nhóm", count: repository.ungroupedCount, filter: .ungrouped)
                }
            }
            .padding(.horizontal)
        }
    }

    private func groupChip(title: String, count: Int, filter: LegadoSourceTabState.GroupFilter) -> some View {
        let isSelected = state.groupFilter == filter
        return Button(action: { state.groupFilter = filter }) {
            Text("\(title) \(count)")
                .font(.caption.weight(isSelected ? .semibold : .regular))
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(isSelected ? Color.accentColor.opacity(0.85) : Color(.secondarySystemBackground))
                .foregroundColor(isSelected ? .white : .primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Trạng thái

    private func statusLine(visible: [LegadoSourceSummary]) -> some View {
        let enabled = visible.reduce(0) { $0 + ($1.isEnabled ? 1 : 0) }
        return HStack(spacing: 6) {
            Text("Đang bật \(enabled)/\(visible.count)")
                .font(.caption)
                .foregroundColor(.secondary)
            if repository.isLoading {
                ProgressView()
                    .scaleEffect(0.7)
            }
            Spacer()
            if state.isBusy {
                ProgressView()
                    .scaleEffect(0.7)
                Text(state.busyMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Danh sách

    @ViewBuilder
    private func content(all: [LegadoSourceSummary], visible: [LegadoSourceSummary]) -> some View {
        if all.isEmpty {
            emptyState(
                icon: "tray",
                message: repository.hasLoaded
                    ? "Chưa có nguồn Legado. Mở menu ⋯ ở góc trên bên phải để nhập nguồn từ tệp JSON, URL hoặc bộ nhớ tạm."
                    : "Đang nạp danh sách nguồn…"
            )
        } else if visible.isEmpty {
            emptyState(icon: "magnifyingglass", message: "Không có nguồn nào khớp bộ lọc.")
        } else {
            List(visible) { summary in
                LegadoSourceRowView(
                    summary: summary,
                    onToggle: { toggle(summary, enabled: $0) },
                    onDelete: { delete(summary) }
                )
            }
            .listStyle(.plain)
        }
    }

    private func emptyState(icon: String, message: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: icon)
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Thao tác

    private func toggle(_ summary: LegadoSourceSummary, enabled: Bool) {
        let packageId = summary.packageId
        Task { @MainActor in
            if case .failure(let error) = await LegadoSourceCoordinator.shared.setEnabled(enabled, packageIds: [packageId]) {
                state.alert = .error(error.localizedDescription)
            }
        }
    }

    /// Xoá ngay, không hỏi lại — giống gỡ tiện ích ở tab "Tất cả tiện ích".
    private func delete(_ summary: LegadoSourceSummary) {
        let packageId = summary.packageId
        Task { @MainActor in
            if case .failure(let error) = await LegadoSourceCoordinator.shared.delete(packageId: packageId) {
                state.alert = .error(error.localizedDescription)
            }
        }
    }
}
