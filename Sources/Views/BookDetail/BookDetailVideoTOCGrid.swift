import SwiftUI

/// Mục lục dạng **tab theo section** cho tab "Mục lục" của màn Chi tiết khi nội dung là video.
///
/// Mỗi dòng `type: "section"` của mục lục thành **một tab** ("Vietsub", "Thuyết minh"…); chọn tab nào thì lưới
/// hiện đúng bộ tập của nhóm đó, số tập đánh lại từ 1. Không còn cắt nhóm thành các cụm số (`1–24`, `25–48`…)
/// như bản 1.3.543 — mốc số không có nghĩa với người xem, còn tên nhóm thì có.
///
/// Hợp đồng: view **không** đọc SwiftData, không gọi mạng — mọi thao tác đi qua closure của màn cha.
/// Ô chỉ hiển thị số thứ tự trong tab; chạm ô trả về `index` thật của chương.
struct BookDetailVideoTOCGrid: View {
    /// Một dòng mục lục đã chuẩn hoá từ `StoredChapterSnapshot` / `Chapter` / `ChapterResult`.
    struct Row: Identifiable, Equatable {
        /// Chỉ số chương thật — khoá để mở chương, **không** dùng để hiển thị.
        let index: Int
        let title: String
        /// Dòng `type: "section"` — tên nhóm, không chạm được.
        let isSection: Bool
        let isCached: Bool

        var id: Int { index }
    }

    /// Một tab: đúng một section của mục lục (không cắt khúc).
    struct SectionGroup: Identifiable {
        let id: Int
        let title: String
        let rows: [Row]

        /// Nhóm đứng trước section đầu tiên không có tên — gọi là "Khác" cho dễ đọc.
        var label: String { title.isEmpty ? "Khác" : title }
    }

    let rows: [Row]
    let currentIndex: Int
    let isAscending: Bool
    let isLoading: Bool
    let errorMessage: String
    /// "tập" với video — dùng cho tiêu đề, placeholder và nhãn trợ năng.
    let noun: String
    /// Số trang mục lục còn lại chưa nạp (0 = không hiện nút "Tải thêm").
    let remainingPages: Int
    @Binding var searchQuery: String

    let onToggleSort: () -> Void
    let onSelect: (Int) -> Void
    let onReload: () -> Void
    let onLoadMore: () -> Void

    @State private var isSearchVisible = false
    @State var selectedGroup = 0

    private static let columnsPerRow = 4
    private static let cellHeight: CGFloat = 46
    private static let spacing: CGFloat = 7
    /// Tối đa chừng này tab thì chia đều bề ngang; nhiều hơn thì cho cuộn ngang để tên không bị cắt.
    static let maxEvenTabs = 3

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: BookDetailVideoTOCGrid.spacing),
        count: BookDetailVideoTOCGrid.columnsPerRow
    )

    var body: some View {
        VStack(spacing: 0) {
            toolbar

            if isSearchVisible {
                searchField
            }

            if rows.isEmpty {
                emptyState
            } else {
                if showsTabs {
                    sectionTabs
                }
                gridScroller
            }
        }
        .onAppear(perform: syncGroupToCurrent)
        .onChange(of: currentIndex) { _, _ in syncGroupToCurrent() }
        .onChange(of: rows) { _, _ in syncGroupToCurrent() }
    }

    // MARK: - Thanh công cụ

    private var toolbar: some View {
        HStack(spacing: 8) {
            Text("Danh sách \(noun)")
                .font(.subheadline.weight(.semibold))

            Text("\(visibleRows.count)")
                .font(.caption2.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.primary.opacity(0.08)))

            Spacer(minLength: 8)

            sortMenu
            searchToggle
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    /// Pill có nhãn thay cho icon `arrow.down.circle` trần của bản cũ — nhìn là biết đang xếp chiều nào.
    private var sortMenu: some View {
        Menu {
            Button {
                if !isAscending { onToggleSort() }
            } label: {
                sortLabel("Cũ nhất trước", isSelected: isAscending)
            }
            Button {
                if isAscending { onToggleSort() }
            } label: {
                sortLabel("Mới nhất trước", isSelected: !isAscending)
            }
        } label: {
            HStack(spacing: 4) {
                Text(isAscending ? "Cũ nhất" : "Mới nhất")
                    .font(.caption.weight(.semibold))
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background(Capsule().fill(Color.primary.opacity(0.08)))
        }
        .accessibilityLabel("Sắp xếp \(noun)")
    }

    @ViewBuilder
    private func sortLabel(_ title: String, isSelected: Bool) -> some View {
        if isSelected {
            Label(title, systemImage: "checkmark")
        } else {
            Text(title)
        }
    }

    private var searchToggle: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) { isSearchVisible.toggle() }
        } label: {
            Image(systemName: isSearchVisible ? "xmark" : "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.primary.opacity(0.08)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isSearchVisible ? "Ẩn tìm kiếm" : "Tìm \(noun)")
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            TextField("Tìm \(noun)...", text: $searchQuery)
                .textFieldStyle(.plain)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.subheadline)

            if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Xoá từ khoá")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color.primary.opacity(0.06)))
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    // MARK: - Tab theo section

    private var showsTabs: Bool {
        !isFiltering && groups.count > 1
    }

    @ViewBuilder
    private var sectionTabs: some View {
        if groups.count <= Self.maxEvenTabs {
            HStack(spacing: 4) {
                ForEach(groups) { group in
                    tab(group, fillsWidth: true)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(groups) { group in
                        tab(group, fillsWidth: false)
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 10)
        }
    }

    private func tab(_ group: SectionGroup, fillsWidth: Bool) -> some View {
        let isSelected = group.id == activeGroup?.id
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) { selectedGroup = group.id }
        } label: {
            HStack(spacing: 6) {
                Text(group.label)
                    .lineLimit(1)
                Text("\(group.rows.count)")
                    .font(.caption2.weight(.bold))
                    .monospacedDigit()
                    .opacity(0.55)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(isSelected ? Color(.systemBackground) : Color.primary.opacity(0.72))
            .padding(.horizontal, 12)
            .frame(maxWidth: fillsWidth ? .infinity : nil)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isSelected ? Color.primary : Color.primary.opacity(0.07))
            )
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(group.label), \(group.rows.count) \(noun)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Lưới

    private var gridScroller: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Color.clear.frame(height: 0).id("grid-top")

                    LazyVGrid(columns: columns, spacing: Self.spacing) {
                        ForEach(Array(visibleRows.enumerated()), id: \.element.id) { offset, row in
                            cell(row, number: displayNumber(for: offset))
                        }
                    }
                    .padding(.horizontal, 16)

                    if remainingPages > 0 {
                        loadMoreButton
                    }

                    if !isFiltering, !visibleRows.isEmpty {
                        endMarker
                    }
                }
                .padding(.bottom, 24)
            }
            .onChange(of: selectedGroup) { _, _ in
                proxy.scrollTo("grid-top", anchor: .top)
            }
        }
    }

    /// Số tập hiển thị: 1…N trong tab; sắp xếp giảm dần thì đánh ngược để số vẫn là số tập.
    private func displayNumber(for offset: Int) -> Int {
        isAscending ? offset + 1 : visibleRows.count - offset
    }

    private func cell(_ row: Row, number: Int) -> some View {
        let isCurrent = row.index == currentIndex
        let isRead = currentIndex >= 0 && row.index < currentIndex

        return Button {
            onSelect(row.index)
        } label: {
            Text("\(number)")
                .font(.system(size: 14, weight: isCurrent ? .bold : .semibold))
                .monospacedDigit()
                .foregroundStyle(isCurrent ? Color(.systemBackground) : Color.primary.opacity(isRead ? 0.36 : 1))
                .frame(maxWidth: .infinity)
                .frame(height: Self.cellHeight)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(isCurrent ? Color.primary : Color.primary.opacity(isRead ? 0.04 : 0.07))
                )
                .overlay(alignment: .topTrailing) {
                    if row.isCached && !isCurrent {
                        Circle()
                            .fill(Color.primary.opacity(0.45))
                            .frame(width: 4, height: 4)
                            .padding(6)
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(noun) \(number): \(row.title)")
        .accessibilityValue(isCurrent ? "Đang xem" : "")
    }

    private var loadMoreButton: some View {
        Button(action: onLoadMore) {
            Text("Tải thêm \(noun) (còn \(remainingPages) trang)")
                .font(.footnote.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 9).fill(Color.primary.opacity(0.08)))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    private var endMarker: some View {
        HStack(spacing: 10) {
            Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1)
            Text(endLabel)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize()
            Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
    }

    // MARK: - Trạng thái rỗng

    @ViewBuilder
    private var emptyState: some View {
        if isLoading {
            ProgressView("Đang tải danh sách \(noun)...")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
        } else if !errorMessage.isEmpty {
            VStack(spacing: 12) {
                Text(errorMessage)
                    .font(.subheadline)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                Button("Tải lại mục lục", action: onReload)
                    .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 30)
        } else {
            Text("Không tìm thấy \(noun) nào hoặc lỗi tải \(noun)")
                .font(.subheadline)
                .foregroundStyle(.gray)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
        }
    }
}
