import SwiftUI

/// Tab Dấu trang / Ghi chú của sheet mục lục Reader (1.3.1040, anh Bửu: "thêm tab ở ghi chú dấu trang ở mục lục", "bấm
/// vào ghi chú để đến đoạn ghi chú, bấm vào đánh dấu để đến chương đánh dấu"). Chip kiểu `ExtensionKindFilterBar` (chữ
/// màu nhấn, nền nhấn ~18%, viền ~60%), màu chữ / vạch theo nền đọc (`tocPalette`). Chạm hàng ⇒ `onOpenAnnotation`
/// (Reader đóng sheet rồi nhảy); 🗑 xoá; nhấn giữ ghi chú ⇒ Sửa / Xoá. Dữ liệu ở `BookAnnotationRepository`.
extension ReaderChapterListView {
    /// Chỉ truyện có trong thư viện (cùng điều kiện ghi được của Reader).
    var showsAnnotationTabs: Bool { localBook != nil && onOpenAnnotation != nil }

    private var annotations: BookAnnotations {
        BookAnnotationRepository.shared.annotations(for: bookId)
    }

    // MARK: - Chip

    var annotationTabBar: some View {
        let value = annotations
        return HStack(spacing: 8) {
            tabChip(.chapters, title: "Mục lục")
            tabChip(.bookmarks, title: "Dấu trang", count: value.bookmarks.count)
            tabChip(.notes, title: "Ghi chú", count: value.notes.count)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, HeaderMetrics.horizontalMargin)
        .padding(.top, 12)
    }

    private func tabChip(_ tab: ReaderChapterListTab, title: String, count: Int? = nil) -> some View {
        let isSelected = selectedTab == tab
        return Button {
            selectedTab = tab
        } label: {
            Text(count.map { "\(title) \($0)" } ?? title)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? .accentColor : tocPalette.secondaryText)
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(Capsule().fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear))
                .overlay(Capsule().stroke(isSelected ? Color.accentColor.opacity(0.6) : tocPalette.divider, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Dấu trang

    var bookmarkList: some View {
        let bookmarks = annotations.sortedBookmarks
        return List {
            if bookmarks.isEmpty {
                emptyRow("Chưa có dấu trang. Bấm biểu tượng dấu trang trên đầu trang đọc để đánh dấu chương.")
            }
            ForEach(bookmarks) { bookmark in
                bookmarkRow(bookmark)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func bookmarkRow(_ bookmark: BookAnnotations.Bookmark) -> some View {
        let isCurrent = bookmark.chapterIndex == currentChapterIndex
        return HStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "bookmark.fill")
                    .font(.subheadline)
                    .foregroundColor(isCurrent ? .accentColor : tocPalette.secondaryText)
                VStack(alignment: .leading, spacing: 2) {
                    Text(chapterLabel(index: bookmark.chapterIndex, title: bookmark.chapterTitle))
                        .font(.body)
                        .foregroundColor(isCurrent ? .accentColor : tocPalette.text)
                        .lineLimit(2)
                    Text(isCurrent ? "\(Self.dateText(bookmark.createdAt)) · đang đọc" : Self.dateText(bookmark.createdAt))
                        .font(.caption)
                        .foregroundColor(tocPalette.secondaryText)
                }
                Spacer(minLength: 8)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                onOpenAnnotation?(bookmark.chapterIndex, bookmark.chapterUrl, -1)
            }

            deleteButton(label: "Xoá dấu trang") {
                BookAnnotationRepository.shared.deleteBookmark(bookId: bookId, id: bookmark.id)
            }
        }
        .padding(.vertical, 4)
        .listRowBackground(Color.clear)
        .listRowSeparatorTint(tocPalette.divider)
        .accessibilityAction(named: "Mở chương") { onOpenAnnotation?(bookmark.chapterIndex, bookmark.chapterUrl, -1) }
    }

    // MARK: - Ghi chú

    var noteList: some View {
        let groups = annotations.notesByChapter
        return List {
            if groups.isEmpty {
                emptyRow("Chưa có ghi chú. Bôi đen chữ trong trang đọc rồi chọn \"Ghi chú\".")
            }
            ForEach(groups) { group in
                Section {
                    ForEach(group.notes) { note in
                        noteRow(note)
                    }
                } header: {
                    Text(chapterLabel(index: group.chapterIndex, title: group.chapterTitle))
                        .font(.footnote)
                        .foregroundColor(tocPalette.secondaryText)
                        .textCase(nil)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .sheet(item: $editingNoteRequest) { request in
            Group { ReaderNoteEditorSheet(request: request) }.appGlassSheet()
        }
    }

    private func noteRow(_ note: BookAnnotations.Note) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                if !note.quote.isEmpty {
                    Text(note.quote)
                        .font(.subheadline)
                        .foregroundColor(tocPalette.secondaryText)
                        .lineLimit(2)
                        .padding(.leading, 8)
                        .overlay(alignment: .leading) {
                            Rectangle().fill(Color.accentColor).frame(width: 2)
                        }
                }
                Text(note.text)
                    .font(.body)
                    .foregroundColor(tocPalette.text)
                    .lineLimit(4)
                Text(noteMeta(note))
                    .font(.caption)
                    .foregroundColor(tocPalette.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                onOpenAnnotation?(note.chapterIndex, note.chapterUrl, note.paragraphIndex)
            }
            .contextMenu {
                Button { editNote(note) } label: { Label("Sửa", systemImage: "square.and.pencil") }
                Button(role: .destructive) {
                    BookAnnotationRepository.shared.deleteNote(bookId: bookId, id: note.id)
                } label: {
                    Label("Xoá", systemImage: "trash")
                }
            }

            deleteButton(label: "Xoá ghi chú") {
                BookAnnotationRepository.shared.deleteNote(bookId: bookId, id: note.id)
            }
        }
        .padding(.vertical, 4)
        .listRowBackground(Color.clear)
        .listRowSeparatorTint(tocPalette.divider)
        .accessibilityAction(named: "Sửa") { editNote(note) }
    }

    private func editNote(_ note: BookAnnotations.Note) {
        editingNoteRequest = ReaderNoteEditorSheet.Request(bookId: bookId, note: note, isNew: false)
    }

    private func noteMeta(_ note: BookAnnotations.Note) -> String {
        let date = Self.dateText(note.updatedAt)
        return note.paragraphNumber > 0 ? "Đoạn \(note.paragraphNumber) · \(date)" : date
    }

    // MARK: - Dùng chung

    private func deleteButton(label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "trash")
                .font(.subheadline)
                .foregroundColor(.red)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(label)
    }

    private func emptyRow(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundColor(tocPalette.secondaryText)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }

    /// Tên chương đã lưu lúc tạo; trống ⇒ "Chương N".
    private func chapterLabel(index: Int, title: String) -> String {
        title.isEmpty ? "Chương \(index + 1)" : title
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "vi_VN")
        formatter.dateFormat = "dd/MM · HH:mm"
        return formatter
    }()

    static func dateText(_ date: Date) -> String {
        dateFormatter.string(from: date)
    }
}
