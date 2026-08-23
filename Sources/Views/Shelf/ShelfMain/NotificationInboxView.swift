import SwiftUI
import SwiftData

/// Trung tâm thông báo: gộp **hai** loại nội dung trong một danh sách nhóm theo ngày —
/// (1) truyện có chương mới (từ [`NewChapterInboxManager`](../../../Services/NewChapters/NewChapterInboxManager.swift),
/// hiện rõ **mỗi truyện cập nhật mấy chương**) và (2) nhật ký toast đã hiện
/// (từ [`NotificationInboxManager`](../../../Common/Services/NotificationInboxManager.swift)).
///
/// Là View nên được phép `@Query` để tra tên truyện; không tự ghi SwiftData — mọi trạng thái đọc/xoá
/// đi qua hai manager.
struct NotificationInboxView: View {
    /// Mở truyện có chương mới; ShelfView chịu trách nhiệm present Reader.
    let onOpenBook: (Book) -> Void

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Book.lastReadDate, order: .reverse) private var allBooks: [Book]
    @ObservedObject private var newChapters = NewChapterInboxManager.shared
    @ObservedObject private var inbox = NotificationInboxManager.shared

    /// Một dòng trong danh sách: truyện có chương mới hoặc một toast đã hiện.
    private enum InboxItem: Identifiable {
        case newChapter(NewChapterRecord)
        case toast(NotificationInboxRecord)

        var id: String {
            switch self {
            case .newChapter(let record): return "new-\(record.bookId)"
            case .toast(let record): return "toast-\(record.id.uuidString)"
            }
        }

        /// Thời điểm dùng để nhóm/sắp xếp.
        var date: Date {
            switch self {
            case .newChapter(let record): return record.firstFoundAt ?? record.lastCheckedAt ?? .distantPast
            case .toast(let record): return record.date
            }
        }

        /// Chương mới xếp trước toast trong cùng một ngày.
        var sortRank: Int {
            switch self {
            case .newChapter: return 0
            case .toast: return 1
            }
        }
    }

    private var bookLookup: [String: Book] {
        Dictionary(allBooks.map { ($0.bookId, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private var newChapterItems: [InboxItem] {
        newChapters.records.values
            .filter { $0.hasNew }
            .map { InboxItem.newChapter($0) }
    }

    private var toastItems: [InboxItem] {
        inbox.records.map { InboxItem.toast($0) }
    }

    /// Gộp rồi nhóm theo ngày; ngày mới nhất trước, trong ngày thì chương mới trước, còn lại theo giờ giảm dần.
    private var groupedByDay: [(day: Date, items: [InboxItem])] {
        let all = newChapterItems + toastItems
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: all) { calendar.startOfDay(for: $0.date) }
        return grouped.keys.sorted(by: >).map { day in
            let items = (grouped[day] ?? []).sorted { lhs, rhs in
                if lhs.sortRank != rhs.sortRank { return lhs.sortRank < rhs.sortRank }
                return lhs.date > rhs.date
            }
            return (day: day, items: items)
        }
    }

    private var isEmpty: Bool {
        newChapterItems.isEmpty && toastItems.isEmpty
    }

    var body: some View {
        NavigationStack {
            Group {
                if isEmpty {
                    emptyState
                } else {
                    inboxList
                }
            }
            .navigationTitle("Thông báo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
        }
        .task { await inbox.loadIfNeeded() }
    }

    // MARK: - Danh sách

    private var inboxList: some View {
        List {
            ForEach(groupedByDay, id: \.day) { group in
                Section {
                    ForEach(group.items) { item in
                        row(for: item)
                    }
                } header: {
                    Text(dayTitle(group.day))
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    @ViewBuilder
    private func row(for item: InboxItem) -> some View {
        switch item {
        case .newChapter(let record):
            newChapterRow(record)
        case .toast(let record):
            toastRow(record)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        inbox.delete(record)
                    } label: {
                        Label("Xoá", systemImage: "trash")
                    }
                }
        }
    }

    private func newChapterRow(_ record: NewChapterRecord) -> some View {
        let book = bookLookup[record.bookId]
        return Button {
            newChapters.markSeen(bookId: record.bookId)
            if let book {
                dismiss()
                onOpenBook(book)
            }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "bell.badge.fill")
                    .foregroundColor(.orange)
                    .font(.title3)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text(bookTitle(for: record, book: book))
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)
                        .lineLimit(2)
                    Text(newChapterSubtitle(record))
                        .font(.footnote.weight(.medium))
                        .foregroundColor(.orange)
                    if !record.latestChapterTitle.isEmpty {
                        Text("Mới nhất: \(record.latestChapterTitle)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func toastRow(_ record: NotificationInboxRecord) -> some View {
        HStack(alignment: .top, spacing: 12) {
            toastIcon(record.type)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(record.message)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .lineLimit(4)
                Text(timeLabel(record.date))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 0)
            if !record.isRead {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 8, height: 8)
                    .padding(.top, 6)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func toastIcon(_ type: ToastType) -> some View {
        switch type {
        case .success:
            Image(systemName: "checkmark.circle.fill").foregroundColor(.green).font(.title3)
        case .error:
            Image(systemName: "exclamationmark.circle.fill").foregroundColor(.red).font(.title3)
        case .info:
            Image(systemName: "info.circle.fill").foregroundColor(.blue).font(.title3)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bell.slash")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text("Chưa có thông báo")
                .font(.headline)
            Text("Chương mới và các thông báo trong app sẽ hiện ở đây, nhóm theo ngày.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Đóng") { dismiss() }
        }
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button {
                    markEverythingRead()
                } label: {
                    Label("Đánh dấu đã đọc hết", systemImage: "checkmark.circle")
                }
                Button(role: .destructive) {
                    inbox.clearAll()
                } label: {
                    Label("Dọn dẹp nhật ký toast", systemImage: "trash")
                }
                .disabled(inbox.records.isEmpty)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .disabled(isEmpty)
        }
    }

    /// "Đánh dấu đã đọc hết": đọc mọi toast + tắt badge mọi truyện có chương mới.
    private func markEverythingRead() {
        inbox.markAllRead()
        for record in newChapters.records.values where record.hasNew {
            newChapters.markSeen(bookId: record.bookId)
        }
    }

    // MARK: - Định dạng

    private func bookTitle(for record: NewChapterRecord, book: Book?) -> String {
        if let title = book?.title, !title.isEmpty {
            return TranslateUtils.translateBookTitleIfNeeded(title, bookId: record.bookId)
        }
        return record.latestChapterTitle.isEmpty ? "Truyện" : record.latestChapterTitle
    }

    private func newChapterSubtitle(_ record: NewChapterRecord) -> String {
        guard record.newChapterCount > 0 else { return "Có chương mới" }
        if record.isCountExact {
            return "\(record.newChapterCount) chương mới"
        }
        return "≥\(record.newChapterCount) chương mới"
    }

    private func dayTitle(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Hôm nay" }
        if calendar.isDateInYesterday(day) { return "Hôm qua" }
        return Self.dayFormatter.string(from: day)
    }

    private func timeLabel(_ date: Date) -> String {
        Self.timeFormatter.string(from: date)
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "vi_VN")
        formatter.dateFormat = "EEEE, d MMMM yyyy"
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "vi_VN")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}
