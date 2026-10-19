import SwiftUI
import SwiftData

/// Hai trang **Kệ sách** và **Lịch sử** của `ShelfView`: thanh chip lọc loại, các trạng thái rỗng, và danh sách dựng
/// qua `ShelfBooksLayoutView` theo kiểu hiển thị đã chọn (danh sách / lưới / chỉ bìa).
///
/// Thanh chip là phần tử **đầu tiên bên trong** từng trang chứ không nằm trên `TabView` page: đặt ngoài thì vuốt từ
/// Bộ sưu tập sang Kệ sách thanh chip bật ra làm nội dung nhảy xuống. Hai trang dùng chung một lựa chọn
/// (`shelfKindFilter`); `ShelfKindFilter` được tính một lần mỗi body rồi truyền xuống cả hai.
///
/// Tách khỏi `ShelfView.swift` để file gốc không phình thêm (baseline dòng). `private` trong Swift là phạm vi
/// **file**, nên các `@State` mà khối này chạm tới (`shelfLimit`, `historyLimit`, `readerPresentationRoute`,
/// `actionTarget`, `shelfKindFilter`) là `internal`.
@MainActor
extension ShelfView {
    internal func shelfTabView(_ parts: ShelfBookPartition, _ filter: ShelfKindFilter) -> some View {
        Group {
            if parts.isShelfEmpty {
                shelfEmptyState(
                    icon: "books.vertical",
                    title: "Kệ sách của bạn đang trống",
                    message: "Đi tới phần Tìm Kiếm hoặc Khám Phá để thêm các truyện yêu thích vào kệ sách."
                )
            } else {
                VStack(spacing: 0) {
                    kindFilterBar(filter)

                    if filter.isShelfEmpty {
                        filteredEmptyState(filter, place: "trên kệ")
                    } else {
                        ShelfBooksLayoutView(
                            groups: shelfGroups(filter),
                            extensions: allExtensions,
                            scope: filter.scope,
                            hasMore: filter.unpinned.count > shelfLimit,
                            onLoadMore: {
                                shelfLimit += 50
                            },
                            onTap: { book in
                                newChapters.markSeen(bookId: book.bookId)
                                openReader(book)
                            },
                            onLongPress: { book in
                                BookSheetAction.playLongPressFeedback()
                                actionTarget = BookSheetAction.Target(book: book, mode: .shelf)
                            }
                        )
                    }
                }
            }
        }
    }

    internal func historyTabView(_ parts: ShelfBookPartition, _ filter: ShelfKindFilter) -> some View {
        Group {
            if parts.history.isEmpty {
                shelfEmptyState(
                    icon: "clock.arrow.circlepath",
                    title: "Lịch sử đọc trống",
                    message: "Lịch sử sẽ tự động ghi nhớ sau khi bạn bắt đầu đọc một chương truyện."
                )
            } else {
                VStack(spacing: 0) {
                    kindFilterBar(filter)

                    if filter.history.isEmpty {
                        filteredEmptyState(filter, place: "trong lịch sử")
                    } else {
                        ShelfBooksLayoutView(
                            groups: historyGroups(filter),
                            extensions: allExtensions,
                            scope: filter.scope,
                            hasMore: filter.history.count > historyLimit,
                            onLoadMore: {
                                historyLimit += 50
                            },
                            // Lịch sử không `markSeen` — giữ đúng hành vi cũ của hàng lịch sử.
                            onTap: { book in
                                openReader(book)
                            },
                            onLongPress: { book in
                                BookSheetAction.playLongPressFeedback()
                                actionTarget = BookSheetAction.Target(book: book, mode: .history)
                            }
                        )
                    }
                }
            }
        }
    }

    // MARK: - Nhóm truyện

    /// Phân trang 50/lượt (sau khi lọc loại) **chỉ** áp cho nhóm chưa ghim: nhóm ghim luôn hiện đủ vì người dùng chủ
    /// động ghim. Chưa ghim truyện nào thì kệ chỉ có một nhóm không tiêu đề — bố cục giống hệt trước 1.3.334.
    private func shelfGroups(_ filter: ShelfKindFilter) -> [ShelfBooksLayoutView.BookGroup] {
        let visibleUnpinned = Array(filter.unpinned.prefix(shelfLimit))
        guard !filter.pinned.isEmpty else {
            return [ShelfBooksLayoutView.BookGroup(id: "unpinned", books: visibleUnpinned)]
        }
        return [
            ShelfBooksLayoutView.BookGroup(
                id: "pinned",
                header: ShelfBooksLayoutView.Header(
                    title: "Đang ghim",
                    icon: "pin.fill",
                    color: .orange,
                    count: filter.pinned.count
                ),
                books: filter.pinned
            ),
            ShelfBooksLayoutView.BookGroup(
                id: "unpinned",
                header: ShelfBooksLayoutView.Header(
                    title: "Truyện khác",
                    icon: "books.vertical",
                    color: .secondary,
                    count: filter.unpinned.count
                ),
                books: visibleUnpinned
            )
        ]
    }

    /// Mỗi ngày một nhóm, tiêu đề cùng khuôn với "Đang ghim"/"Truyện khác" — gom nhóm ở `HistoryDayGrouper`, **sau**
    /// khi cắt `historyLimit` (nhóm cuối có thể là một ngày dở, đúng hành vi phân trang cũ).
    private func historyGroups(_ filter: ShelfKindFilter) -> [ShelfBooksLayoutView.BookGroup] {
        HistoryDayGrouper.group(Array(filter.history.prefix(historyLimit))).map { day in
            ShelfBooksLayoutView.BookGroup(
                id: "day-\(day.id)",
                header: ShelfBooksLayoutView.Header(
                    title: day.label,
                    icon: "clock",
                    color: .secondary,
                    count: day.books.count
                ),
                books: day.books
            )
        }
    }

    private func openReader(_ book: Book) {
        readerPresentationRoute = ShelfReaderRoute(
            bookId: book.bookId,
            extensionPackageId: book.extensionPackageId,
            chapterIndex: book.currentChapterIndex,
            paragraphIndex: nil,
            detailUrl: book.detailUrl,
            sourceName: book.sourceName
        )
    }

    // MARK: - Chip lọc + trạng thái rỗng

    /// Ẩn khi kệ ∪ lịch sử chỉ có một loại (`ShelfKindFilter.showsFilterBar`) — khi đó mọi thứ hiện như "Tất cả".
    @ViewBuilder
    private func kindFilterBar(_ filter: ShelfKindFilter) -> some View {
        if filter.showsFilterBar {
            ExtensionKindFilterBar(selection: $shelfKindFilter)
        }
    }

    /// Lọc theo chip ra 0 truyện (kệ/lịch sử vẫn còn truyện loại khác). Thanh chip vẫn ở trên để chọn lại.
    private func filteredEmptyState(_ filter: ShelfKindFilter, place: String) -> some View {
        let kind = filter.selectedKind ?? .text
        return VStack(spacing: 12) {
            Image(systemName: kind.symbolName)
                .font(.system(size: 44))
                .foregroundColor(.secondary)

            Text("Chưa có \(kind.label.lowercased()) \(place)")
                .font(.headline)
                .multilineTextAlignment(.center)

            Text("Chọn \"Tất cả\" để xem các truyện khác.")
                .font(.subheadline)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Kệ / lịch sử chưa có truyện nào (chưa xét chip) — giữ nguyên trạng thái rỗng cũ.
    private func shelfEmptyState(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 80, height: 80)
                .foregroundColor(.secondary)

            Text(title)
                .font(.title3)
                .fontWeight(.semibold)

            Text(message)
                .font(.subheadline)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxHeight: .infinity)
    }
}
