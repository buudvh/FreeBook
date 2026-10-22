import SwiftUI

/// Nội dung tab "Nguồn Legado" của màn Kho Tiện Ích: ô tìm, hàng chip nhóm (có số đếm), dòng "Đang bật x/y" và danh
/// sách nguồn. Mọi thao tác ghi đi qua `LegadoSourceCoordinator`; menu ⋯ (nhập, bật/tắt hàng loạt, kiểm tra, xuất,
/// xoá tất cả) nằm ở toolbar của `RepositoryManagerView` và dùng chung `state`.
///
/// Công tắc NSFW chung (`includeNsfw`, `@AppStorage` của view cha — đọc trong `body` nên tự vẽ lại) tắt ⇒ ẩn nguồn 18+;
/// chip nhóm và "Đang bật x/y" tính trên danh sách **sau** lọc. Chạm vào dòng ⇒ màn chi tiết (sheet).
///
/// Danh sách có thể vài nghìn dòng: `List` lười, lọc một lần mỗi lượt vẽ trên `searchKey` đã tính sẵn.
struct LegadoSourceListView: View {
    @Binding var state: LegadoSourceTabState
    let includeNsfw: Bool

    private var repository: LegadoSourceRepository { LegadoSourceRepository.shared }

    var body: some View {
        let all = repository.summaries
        let nsfwIds = repository.nsfwPackageIds
        let pool = state.nsfwFiltered(all, includeNsfw: includeNsfw, nsfwIds: nsfwIds)
        let visible = state.visibleSummaries(all, includeNsfw: includeNsfw, nsfwIds: nsfwIds)

        VStack(spacing: 8) {
            searchField
            groupChips(pool: pool, all: all)
            statusLine(visible: visible, hiddenNsfw: all.count - pool.count)
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

    private func groupChips(pool: [LegadoSourceSummary], all: [LegadoSourceSummary]) -> some View {
        // Không ẩn gì ⇒ dùng số đã tính sẵn của repository; có ẩn ⇒ đếm lại trên danh sách sau lọc.
        let counts: [LegadoSourceGroupCount]
        let ungrouped: Int
        if pool.count == all.count {
            counts = repository.groupCounts
            ungrouped = repository.ungroupedCount
        } else {
            let computed = LegadoSourceTabState.groupCounts(pool)
            counts = computed.counts
            ungrouped = computed.ungrouped
        }
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                groupChip(title: "Tất cả", count: pool.count, filter: .all)
                ForEach(counts) { entry in
                    groupChip(title: entry.translatedGroup, count: entry.count, filter: .group(entry.group))
                }
                if ungrouped > 0 {
                    groupChip(title: "Chưa nhóm", count: ungrouped, filter: .ungrouped)
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
                .background(isSelected ? Color.accentColor.opacity(0.18) : Color(.secondarySystemBackground))
                .foregroundColor(isSelected ? .accentColor : .primary)
                .clipShape(Capsule())
                // App đặt `.tint(.white)` toàn cục ⇒ màu nhấn là trắng: chip chọn theo kiểu `ExtensionKindFilterBar`.
                .overlay(Capsule().stroke(isSelected ? Color.accentColor.opacity(0.6) : Color.white.opacity(0.12), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Trạng thái

    private func statusLine(visible: [LegadoSourceSummary], hiddenNsfw: Int) -> some View {
        let enabled = visible.reduce(0) { $0 + ($1.isEnabled ? 1 : 0) }
        return HStack(spacing: 6) {
            Text("Đang bật \(enabled)/\(visible.count)")
                .font(.caption)
                .foregroundColor(.secondary)
            if hiddenNsfw > 0 {
                Text("· ẩn \(hiddenNsfw) nguồn 18+")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
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
                    onDelete: { delete(summary) },
                    onOpen: { state.detail = LegadoSourceTabState.DetailRoute(packageId: summary.packageId) }
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
