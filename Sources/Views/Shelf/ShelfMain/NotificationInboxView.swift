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
    /// **Không** `private`: khối "Gộp VietPhrase" nằm ở `NotificationInboxView+Merge.swift` và `private` của
    /// Swift giới hạn theo file — để `private` thì file đó không đọc được (CI 1.3.445 đã đỏ đúng vì lỗi này).
    @ObservedObject var mergeTask = DictionaryMergeTask.shared
    /// Hai task "Phiên âm lại từ điển" — **không** `private`: khối card nằm ở
    /// `NotificationInboxView+Rephoneticize.swift`, và `private` của Swift giới hạn theo file (bẫy đã trả giá
    /// ở 1.3.445 với chính khối gộp VietPhrase).
    ///
    /// Cả hai chỉ đọc **JSON meta vài trăm byte** ở `init`/`refreshFromDisk`; `body` **không** chạm đĩa. Đây
    /// là điều kiện để mở màn Thông báo sau khi khởi động lại không bị đơ (bài học 1.3.448).
    @ObservedObject var rephoneticizeNghi = RephoneticizeTask.nghiTTS
    @ObservedObject var rephoneticizeVieNeu = RephoneticizeTask.vieNeu
    @AppStorage("isTranslationEnabled") private var isTranslationEnabled = false

    /// Trạng thái cục bộ của khối "Gộp VietPhrase". Phải khai ở **file chính**: Swift không cho `@State`
    /// trong extension khác file, mà khối đó nằm ở `NotificationInboxView+Merge.swift` vì trần 400 dòng.
    @State var isApplyingMerge = false
    @State var mergeErrorMessage = ""

    /// Một dòng trong danh sách: truyện có chương mới, một toast đã hiện, hoặc mục **Gộp VietPhrase**.
    ///
    /// Không còn `private` vì `mergeTaskRow()` nằm ở file `NotificationInboxView+Merge.swift` (trần 400
    /// dòng); `private` của Swift giới hạn theo file nên extension khác file sẽ không thấy được.
    enum InboxItem: Identifiable {
        case newChapter(NewChapterRecord)
        case toast(NotificationInboxRecord)
        /// Mục "Gộp VietPhrase" — không thuộc hai store trên, trạng thái do `DictionaryMergeTask` giữ.
        /// Mang sẵn `date` để enum này **không** phải chạm vào singleton `@MainActor` từ thuộc tính
        /// không cô lập.
        case mergeTask(date: Date)
        /// Mục "Phiên âm lại từ điển" — **một** case cho **cả hai** từ điển: màn Thông báo đang sát trần 400
        /// dòng nên hai case riêng là nguy cơ vượt trần. Card của từng từ điển do file extension vẽ.
        case rephoneticize(date: Date)

        var id: String {
            switch self {
            case .newChapter(let record): return "new-\(record.bookId)"
            case .toast(let record): return "toast-\(record.id.uuidString)"
            case .mergeTask: return "merge-vietphrase"
            case .rephoneticize: return "rephoneticize-dictionaries"
            }
        }

        /// Thời điểm dùng để nhóm/sắp xếp.
        var date: Date {
            switch self {
            case .newChapter(let record):
                return record.announcedAt ?? record.firstFoundAt ?? record.lastCheckedAt ?? .distantPast
            case .toast(let record):
                return record.date
            case .mergeTask(let date):
                return date
            case .rephoneticize(let date):
                return date
            }
        }

        /// Mục gộp ghim lên đầu (xếp trước cả chương mới), vì nó là việc **đang chờ người dùng quyết định**;
        /// chương mới xếp trước toast. "Phiên âm lại" cùng mức ghim vì cũng đang chờ quyết định.
        var sortRank: Int {
            switch self {
            case .mergeTask, .rephoneticize: return -1
            case .newChapter: return 0
            case .toast: return 1
            }
        }
    }

    private var bookLookup: [String: Book] {
        Dictionary(allBooks.map { ($0.bookId, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Lọc theo **thông báo đã phát**, không theo badge: dòng phải ở lại sau khi đánh dấu đã đọc.
    private var newChapterItems: [InboxItem] {
        newChapters.announcements.map { InboxItem.newChapter($0) }
    }

    private var toastItems: [InboxItem] {
        inbox.records.map { InboxItem.toast($0) }
    }

    /// Mục "Gộp VietPhrase" chỉ có mặt khi đang chạy, đã có file kết quả, hoặc vừa lỗi.
    private var mergeTaskItems: [InboxItem] {
        guard mergeTask.isVisible else { return [] }
        return [InboxItem.mergeTask(date: mergeTask.displayDate)]
    }

    /// Mục "Phiên âm lại" — **một** dòng cho cả hai từ điển, chỉ có mặt khi ít nhất một task đang chạy / có
    /// file kết quả / vừa lỗi. Ngày lấy từ task hiện diện mới nhất; đọc `meta` đã nằm trong RAM.
    private var rephoneticizeItems: [InboxItem] {
        let visible = [rephoneticizeNghi, rephoneticizeVieNeu].filter { $0.isVisible }
        guard !visible.isEmpty else { return [] }
        return [InboxItem.rephoneticize(date: visible.map(\.displayDate).max() ?? Date())]
    }

    /// Gộp rồi nhóm theo ngày; ngày mới nhất trước, trong ngày thì chương mới trước, còn lại theo giờ giảm dần.
    private var groupedByDay: [(day: Date, items: [InboxItem])] {
        let all = mergeTaskItems + rephoneticizeItems + newChapterItems + toastItems
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
        newChapterItems.isEmpty && toastItems.isEmpty && mergeTaskItems.isEmpty && rephoneticizeItems.isEmpty
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
        case .mergeTask:
            // Không có `swipeActions`: mục này chỉ biến mất bằng hành động tường minh (nhập / bỏ qua),
            // để một cú vuốt không xoá mất file kết quả mà người dùng chưa kịp xuất.
            mergeTaskRow()
        case .rephoneticize:
            // Cùng lý do: file kết quả chỉ mất khi người dùng chọn "Nhập vào từ điển" hoặc "Bỏ qua".
            rephoneticizeRow()
        case .newChapter(let record):
            newChapterRow(record)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        newChapters.clearAnnouncement(bookId: record.bookId)
                    } label: {
                        Label("Xoá", systemImage: "trash")
                    }
                }
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
                Image(systemName: record.isAnnouncementRead ? "bell" : "bell.badge.fill")
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
                        Text("Mới nhất: \(displayedChapterTitle(for: record))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                if !record.isAnnouncementRead {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 8, height: 8)
                        .padding(.top, 6)
                }
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
        Button {
            inbox.markRead(record)
        } label: {
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
                        .fill(Color.white)
                        .frame(width: 8, height: 8)
                        .padding(.top, 6)
                }
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(record.isRead ? "" : "Bấm để đánh dấu đã đọc")
    }

    @ViewBuilder
    private func toastIcon(_ type: ToastType) -> some View {
        switch type {
        case .success:
            Image(systemName: "checkmark.circle.fill").foregroundColor(.green).font(.title3)
        case .error:
            Image(systemName: "exclamationmark.circle.fill").foregroundColor(.red).font(.title3)
        case .info:
            Image(systemName: "info.circle.fill").foregroundColor(.white).font(.title3)
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
                    // Không hiện toast xác nhận: `ToastManager.show` lại ghi vào chính hộp thư này.
                    inbox.deleteRead()
                    newChapters.clearReadAnnouncements()
                } label: {
                    Label("Xoá thông báo đã đọc", systemImage: "trash")
                }
                .disabled(!inbox.hasRead && !newChapters.hasReadAnnouncement)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 17, weight: .semibold))
            }
            .disabled(isEmpty)
        }
    }

    /// "Đánh dấu đã đọc hết": đọc mọi toast + mọi dòng chương mới (dòng vẫn ở lại danh sách).
    private func markEverythingRead() {
        inbox.markAllRead()
        newChapters.markAllAnnouncementsRead()
    }

    // MARK: - Định dạng

    private func bookTitle(for record: NewChapterRecord, book: Book?) -> String {
        if let title = book?.title, !title.isEmpty {
            return TranslateUtils.translateBookTitleIfNeeded(title, bookId: record.bookId)
        }
        let fallback = displayedChapterTitle(for: record)
        return fallback.isEmpty ? "Truyện" : fallback
    }

    /// `latestChapterTitle` được `NewChapterProbe` lưu **nguyên văn** từ mục lục nguồn (thường là chữ
    /// Hán), nên phải dịch ở chỗ hiển thị — tên truyện ngay trên nó đã dịch từ trước, để một dòng chữ
    /// Hán bên dưới là lệch. Guard giống `BookListItemView`: chỉ dịch khi công tắc đang bật và chuỗi
    /// thật sự có chữ Hán, nhờ vậy tên chương tiếng Việt/Anh không đi qua bộ dịch một cách vô ích.
    private func displayedChapterTitle(for record: NewChapterRecord) -> String {
        let raw = record.latestChapterTitle
        guard isTranslationEnabled, TranslateUtils.containsChinese(raw) else { return raw }
        return TranslateUtils.translateChapterTitle(raw, bookId: record.bookId)
    }

    /// Đọc **con số của thông báo**, không đọc `newChapterCount`: sau khi đánh dấu đã đọc con số kia
    /// về 0, còn dòng này vẫn phải nói đúng đợt đó có mấy chương.
    private func newChapterSubtitle(_ record: NewChapterRecord) -> String {
        guard record.announcedChapterCount > 0 else { return "Có chương mới" }
        if record.announcedIsCountExact {
            return "\(record.announcedChapterCount) chương mới"
        }
        return "≥\(record.announcedChapterCount) chương mới"
    }

    private func dayTitle(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Hôm nay" }
        if calendar.isDateInYesterday(day) { return "Hôm qua" }
        return Self.dayFormatter.string(from: day)
    }

    /// **Không** `private`: khối "Gộp VietPhrase" ở `NotificationInboxView+Merge.swift` cũng cần định dạng
    /// giờ này (giờ hiện ở góc phải dòng gộp). `private` của Swift giới hạn theo file nên để `private` thì
    /// file đó không gọi được.
    func timeLabel(_ date: Date) -> String {
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
