import SwiftUI

/// Mục lục của màn đọc comic: chương đang đọc được đánh dấu, chương đã tải offline có icon; chạm để nhảy chương.
///
/// `book` (nếu có) dùng cho hai nút ở toolbar trái: **tải ảnh offline** (mở `TaskOptionsSheet` y như nhấn-giữ một
/// truyện ở Kệ/Lịch sử) và **thêm/bỏ kệ** (`ShelfToggleFlowModifier`, cùng luồng với danh sách chương Reader chữ).
/// Sách chưa có trong thư viện thì không có hàng `Book` nên cả hai nút ẩn.
@MainActor
struct ComicChapterListSheet: View {
    let chapters: [ComicChapterEntry]
    let currentIndex: Int
    let downloadedIndexes: Set<Int>
    let isTranslationEnabled: Bool
    let book: Book?
    let onSelect: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var showingDownloadOptions = false
    @State private var isConfirmingShelfRemoval = false
    @State private var collectionPickerBook: Book? = nil

    var body: some View {
        NavigationStack {
            Group {
                if chapters.isEmpty {
                    ContentUnavailableView(
                        "Chưa có mục lục",
                        systemImage: "list.bullet",
                        description: Text("Mở trang chi tiết truyện để tải mục lục.")
                    )
                } else {
                    chapterList
                }
            }
            .navigationTitle("Mục lục (\(readableChapterCount))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 6) {
                        if book != nil, !chapters.isEmpty {
                            Button {
                                showingDownloadOptions = true
                            } label: {
                                Image(systemName: "arrow.down.to.line")
                                    .font(.system(size: 17, weight: .semibold))
                                    .frame(width: 36, height: 38)
                            }
                            .accessibilityLabel("Tải ảnh offline")
                        }
                        shelfToggleButton
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(width: 36, height: 38)
                    }
                    .accessibilityLabel("Đóng")
                }
            }
            .sheet(isPresented: $showingDownloadOptions) {
                if let book {
                    TaskOptionsSheet(book: book, taskType: .download)
                }
            }
            // Gắn ở đây như sheet tải, không gắn trong `ToolbarItem`.
            .shelfToggleFlow(
                book: book,
                displayTitle: displayedBookTitle,
                isConfirmingRemoval: $isConfirmingShelfRemoval,
                collectionPickerBook: $collectionPickerBook
            )
        }
    }

    @ViewBuilder
    private var shelfToggleButton: some View {
        if let book {
            let isOnShelf = book.isOnShelf
            Button {
                ShelfToggleFlowModifier.toggle(
                    book,
                    in: modelContext,
                    isConfirmingRemoval: $isConfirmingShelfRemoval,
                    collectionPickerBook: $collectionPickerBook
                )
            } label: {
                Image(systemName: ShelfToggleFlowModifier.iconName(isOnShelf: isOnShelf))
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 36, height: 38)
            }
            // Chưa ở kệ: màu nhấn như nút tải bên cạnh; đã ở kệ: đỏ (nút bỏ).
            .tint(isOnShelf ? Color.red : nil)
            .accessibilityLabel(ShelfToggleFlowModifier.accessibilityLabel(isOnShelf: isOnShelf))
        }
    }

    /// Tên trong hộp xác nhận bỏ kệ — cùng luật dịch tên với thẻ ở Kệ.
    private var displayedBookTitle: String {
        guard let book else { return "" }
        return BookDisplayTranslation.title(book.title, bookId: book.bookId, isEnabled: isTranslationEnabled)
    }

    private var chapterList: some View {
        ScrollViewReader { proxy in
            List(chapters, id: \.index) { chapter in
                Group {
                    if chapter.isSection {
                        sectionHeader(for: chapter)
                    } else {
                        row(for: chapter)
                    }
                }
                .id(chapter.index)
            }
            .listStyle(.plain)
            .onAppear {
                // Đợi List dựng xong rồi mới cuộn tới chương đang đọc.
                DispatchQueue.main.async {
                    proxy.scrollTo(currentIndex, anchor: .center)
                }
            }
        }
    }

    /// Số chương đọc được — không tính dòng tiêu đề nhóm.
    private var readableChapterCount: Int {
        chapters.reduce(0) { count, chapter in chapter.isSection ? count : count + 1 }
    }

    /// Dòng tiêu đề nhóm tập (`isSection`): chỉ là nhãn, không chạm được.
    private func sectionHeader(for chapter: ComicChapterEntry) -> some View {
        Text(chapter.displayTitle(translated: isTranslationEnabled))
            .font(.subheadline.weight(.bold))
            .foregroundStyle(Color.secondary)
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
            .listRowBackground(Color(.secondarySystemBackground))
            .accessibilityAddTraits(.isHeader)
    }

    private func row(for chapter: ComicChapterEntry) -> some View {
        let isCurrent = chapter.index == currentIndex
        return Button {
            onSelect(chapter.index)
            dismiss()
        } label: {
            HStack(spacing: 10) {
                Text(chapter.displayTitle(translated: isTranslationEnabled))
                    .font(.subheadline.weight(isCurrent ? .semibold : .regular))
                    .foregroundStyle(isCurrent ? Color.accentColor : Color.primary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if downloadedIndexes.contains(chapter.index) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(Color.green)
                        .accessibilityLabel("Đã tải offline")
                }
                if isCurrent {
                    Image(systemName: "book.fill")
                        .font(.footnote)
                        .foregroundStyle(Color.accentColor)
                        .accessibilityLabel("Đang đọc")
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(isCurrent ? Color.accentColor.opacity(0.12) : Color.clear)
    }
}
