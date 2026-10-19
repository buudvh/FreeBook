import SwiftUI

/// Khung danh sách truyện phía kệ (tab Kệ sách, tab Lịch sử, chi tiết Bộ sưu tập, kết quả lưới của Tìm trên kệ),
/// dựng theo kiểu hiển thị của `scope` trong `BookListLayoutPreferences` (đọc trong `body` ⇒ sheet "Kiểu hiển thị"
/// ghi xong là vẽ lại ngay).
///
/// Hai nhánh tách hẳn nhau:
/// - `.list`: `List` `.plain` + `Section` + `ShelfBookRowView`, sentinel `ProgressView` cuối danh sách — y như trước
///   khi có tuỳ chọn kiểu.
/// - `.grid` / `.coverOnly`: `ScrollView` + `LazyVGrid` N cột với `ShelfBookGridCardView`. **`LazyVGrid` tuyệt đối
///   không lồng trong `List`** (crash `EXC_BREAKPOINT` ở 1.3.269, xem `CollectionsTabView`).
///
/// Mọi hàng/thẻ dùng `onTapGesture` + `onLongPressGesture` chứ **không** bọc `Button`: bọc Button thì nhả tay sau khi
/// giữ vẫn kích hoạt action, mở luôn cả Reader. View này chỉ phát sự kiện; rung, `markSeen`, mở Reader/sheet là
/// việc của nơi dùng (mỗi màn có luật riêng — Lịch sử không `markSeen`).
@MainActor
struct ShelfBooksLayoutView: View {
    /// Tiêu đề một nhóm (`ShelfSectionHeaderView`).
    struct Header {
        let title: String
        let icon: String
        let color: Color
        let count: Int
    }

    /// Một nhóm truyện. `header == nil` ⇒ dựng thẳng các hàng, không bọc `Section` (kệ chưa ghim truyện nào, kết
    /// quả Tìm trên kệ) để không có tiêu đề nhóm lơ lửng một mình.
    struct BookGroup: Identifiable {
        let id: String
        var header: Header? = nil
        let books: [Book]
    }

    /// Hành động vuốt ngang của hàng (Bộ sưu tập: "Bỏ khỏi bộ"). Chỉ có ở kiểu danh sách — `LazyVGrid` không có
    /// `swipeActions`; kiểu lưới dựa vào sheet nhấn giữ (đã có cùng mục).
    struct SwipeAction {
        let title: String
        let systemImage: String
        let perform: (Book) -> Void
    }

    let groups: [BookGroup]
    let extensions: [Extension]
    let scope: BookListLayoutScope
    /// Còn truyện chưa hiện (phân trang 50/lượt của nơi dùng) ⇒ có sentinel tải thêm ở cuối.
    var hasMore: Bool = false
    var onLoadMore: () -> Void = {}
    var swipeAction: SwipeAction? = nil
    let onTap: (Book) -> Void
    let onLongPress: (Book) -> Void

    var body: some View {
        let layout = BookListLayoutPreferences.shared.layout(for: scope)
        if layout.mode.isGrid {
            gridView(layout)
        } else {
            listView
        }
    }

    // MARK: - Danh sách

    private var listView: some View {
        List {
            ForEach(groups) { group in
                if let header = group.header {
                    Section {
                        listRows(group.books)
                    } header: {
                        headerView(header)
                    }
                } else {
                    listRows(group.books)
                }
            }

            if hasMore {
                HStack {
                    Spacer()
                    ProgressView()
                        .onAppear { scheduleLoadMore() }
                    Spacer()
                }
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
    }

    private func listRows(_ books: [Book]) -> some View {
        ForEach(books) { book in
            listRow(book)
        }
    }

    @ViewBuilder
    private func listRow(_ book: Book) -> some View {
        let row = ShelfBookRowView(book: book, extensions: extensions)
            .contentShape(Rectangle())
            .onTapGesture {
                onTap(book)
            }
            .onLongPressGesture(minimumDuration: BookSheetAction.longPressMinimumDuration) {
                onLongPress(book)
            }

        if let swipeAction {
            row.swipeActions(edge: .trailing) {
                Button(role: .destructive) {
                    swipeAction.perform(book)
                } label: {
                    Label(swipeAction.title, systemImage: swipeAction.systemImage)
                }
            }
        } else {
            row
        }
    }

    // MARK: - Lưới

    private func gridView(_ layout: BookListLayout) -> some View {
        let columns = Array(
            repeating: GridItem(.flexible(), spacing: 10, alignment: .top),
            count: layout.columns
        )
        let loadedCount = groups.reduce(0) { $0 + $1.books.count }

        // Sentinel nằm trong `LazyVStack` (không phải `VStack`): con của stack thường trong `ScrollView` chạy
        // `onAppear` ngay khi dựng, sentinel sẽ bắn một lần rồi thôi; còn làm một ô của lưới thì chỉ chiếm một cột.
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                LazyVGrid(columns: columns, alignment: .leading, spacing: layout.mode == .coverOnly ? 10 : 14) {
                    ForEach(groups) { group in
                        if let header = group.header {
                            Section {
                                gridCards(group.books, mode: layout.mode)
                            } header: {
                                headerView(header)
                                    .padding(.top, 6)
                            }
                        } else {
                            gridCards(group.books, mode: layout.mode)
                        }
                    }
                }

                if hasMore {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .onAppear { scheduleLoadMore() }
                        // `id` theo số truyện đã hiện, đặt **ngoài** `onAppear`: tải thêm xong mà sentinel vẫn trong
                        // màn hình (lưới bìa ngang nhiều cột rất thấp) thì nó được dựng lại và `onAppear` chạy tiếp,
                        // không kẹt tới khi người dùng cuộn.
                        .id(loadedCount)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    private func gridCards(_ books: [Book], mode: BookListLayoutMode) -> some View {
        ForEach(books) { book in
            ShelfBookGridCardView(
                book: book,
                extensions: extensions,
                mode: mode,
                aspectRatio: scope.coverAspectRatio
            )
            .contentShape(Rectangle())
            .onTapGesture {
                onTap(book)
            }
            .onLongPressGesture(minimumDuration: BookSheetAction.longPressMinimumDuration) {
                onLongPress(book)
            }
        }
    }

    // MARK: - Dùng chung

    private func headerView(_ header: Header) -> ShelfSectionHeaderView {
        ShelfSectionHeaderView(title: header.title, icon: header.icon, color: header.color, count: header.count)
    }

    /// Như bản cũ của Kệ/Lịch sử: nhích 0,3 s rồi mới tăng giới hạn, để lượt tải thêm không chen vào giữa lượt vẽ
    /// đang làm sentinel hiện ra.
    private func scheduleLoadMore() {
        let loadMore = onLoadMore
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            loadMore()
        }
    }
}
