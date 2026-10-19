import SwiftUI

/// Mục lục dạng **lưới tập** cho tab "Mục lục" của màn Chi tiết khi nội dung là video.
///
/// Vì sao có: `BookDetailTOCView` vẽ mỗi chương một hàng có `Divider`; phim 60–120 tập thì danh sách rất dài,
/// hàng không có số tập nên khó nhảy đúng tập, và dòng tiêu đề nhóm không gấp được. View này giữ **nguyên**
/// nguồn dữ liệu của màn Chi tiết (đã lọc/sắp ở `BookDetailTOCView.videoRows`) nhưng trình bày thành:
/// thanh công cụ dính (số tập + kiểu sắp xếp + tìm kiếm), chip chia khoảng theo dòng `section` của mục lục,
/// và lưới 4 cột ô 46pt.
///
/// Hợp đồng: view **không** đọc SwiftData, không gọi mạng — mọi thao tác đi qua closure của màn cha.
/// Chỉ hiển thị `ordinal` (1…N, đếm bỏ qua dòng nhóm); chạm ô thì trả về `index` thật của chương.
struct BookDetailVideoTOCGrid: View {
    /// Một dòng mục lục đã chuẩn hoá từ `StoredChapterSnapshot` / `Chapter` / `ChapterResult`.
    struct Row: Identifiable, Equatable {
        /// Chỉ số chương thật — khoá để mở chương, **không** dùng để hiển thị.
        let index: Int
        /// Số tập hiển thị 1…N (bỏ qua dòng tiêu đề nhóm), không đổi theo chiều sắp xếp.
        let ordinal: Int
        let title: String
        /// Dòng `type: "section"` — tiêu đề nhóm, không chạm được.
        let isSection: Bool
        let isCached: Bool

        var id: Int { index }
    }

    /// Một khoảng tập (một chip): nhóm theo section, nhóm quá dài thì tự cắt khúc.
    struct RangeGroup: Identifiable {
        let id: Int
        let title: String
        let label: String
        let rows: [Row]
    }

    let rows: [Row]
    let totalCount: Int
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
    @State var selectedRange = 0

    private static let columnsPerRow = 4
    private static let cellHeight: CGFloat = 46
    private static let spacing: CGFloat = 7
    /// Một nhóm dài hơn ngưỡng này sẽ bị cắt thành nhiều chip để không phải cuộn quá lâu.
    static let maxRowsPerGroup = 60
    static let chunkSize = 24

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
                if !isFiltering {
                    rangeChips
                }
                gridScroller
            }
        }
        .onAppear(perform: syncRangeToCurrent)
        .onChange(of: currentIndex) { _, _ in syncRangeToCurrent() }
        .onChange(of: rows) { _, _ in syncRangeToCurrent() }
    }

    // MARK: - Thanh công cụ

    private var toolbar: some View {
        HStack(spacing: 8) {
            Text("Danh sách \(noun)")
                .font(.subheadline.weight(.semibold))

            Text("\(totalCount)")
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

    /// Thay cho icon `arrow.down.circle` trần của bản cũ: pill có nhãn nên biết ngay đang xếp chiều nào.
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

    // MARK: - Chip khoảng

    private var rangeChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Self.spacing) {
                ForEach(groups) { group in
                    chip(group)
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 10)
    }

    private func chip(_ group: RangeGroup) -> some View {
        let isSelected = group.id == activeGroup?.id
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) { selectedRange = group.id }
        } label: {
            Text(group.label)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(isSelected ? Color(.systemBackground) : Color.primary.opacity(0.8))
                .padding(.horizontal, 11)
                .frame(height: 28)
                .background(
                    Capsule().fill(isSelected ? Color.primary : Color.primary.opacity(0.08))
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(noun) \(group.label)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Lưới

    private var gridScroller: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Color.clear.frame(height: 0).id("grid-top")

                    if !isFiltering {
                        sectionLabel
                    }

                    LazyVGrid(columns: columns, spacing: Self.spacing) {
                        ForEach(visibleRows) { row in
                            cell(row)
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
            .onChange(of: selectedRange) { _, _ in
                proxy.scrollTo("grid-top", anchor: .top)
            }
        }
    }

    private var sectionLabel: some View {
        HStack(spacing: 7) {
            Capsule()
                .fill(Color.primary.opacity(0.35))
                .frame(width: 3, height: 13)

            Text(groupTitle)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 6)

            Text(activeGroup?.label ?? "")
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private func cell(_ row: Row) -> some View {
        let isCurrent = row.index == currentIndex
        let isRead = currentIndex >= 0 && row.index < currentIndex

        return Button {
            onSelect(row.index)
        } label: {
            Text("\(row.ordinal)")
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
        .accessibilityLabel("\(noun) \(row.ordinal): \(row.title)")
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
