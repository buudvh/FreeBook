import SwiftUI
import SwiftData

/// Phần "hộp thư chương mới" của Kệ sách: dựng target, badge và ba đường refresh.
///
/// Tách sang file riêng để `ShelfView.swift` không phình thêm. Toàn bộ logic mạng/lưu trữ nằm ở
/// [`NewChapterInboxManager`](../../../../Services/NewChapters/NewChapterInboxManager.swift);
/// ở đây chỉ có việc gom dữ liệu từ `@Query` và hiện toast — service không được gọi `ToastManager`.
@MainActor
extension ShelfView {
    /// Truyện online trên kệ, **theo thứ tự đọc gần nhất** (`allBooks` đã sort giảm dần theo
    /// `lastReadDate`) nên khi lượt kiểm tra bị chặn bởi `maxBooksPerBatch` thì truyện đang đọc
    /// được ưu tiên.
    internal var newChapterTargets: [NewChapterProbe.Target] {
        allBooks.compactMap { book in
            guard book.isOnShelf else { return nil }
            return newChapterTarget(for: book)
        }
    }

    /// `nil` khi truyện không thể kiểm tra: truyện nhập cục bộ, thiếu `detailUrl`, hoặc tiện ích
    /// bóc tách chưa tải về máy.
    internal func newChapterTarget(for book: Book) -> NewChapterProbe.Target? {
        guard !book.isLocalBook, !book.detailUrl.isEmpty else { return nil }
        guard let ext = allExtensions.first(where: { $0.packageId == book.extensionPackageId }),
              !ext.localPath.isEmpty else { return nil }

        let host: String?
        if let bookHost = book.host, !bookHost.isEmpty {
            host = bookHost
        } else {
            host = ext.sourceUrl
        }

        return NewChapterProbe.Target(
            bookId: book.bookId,
            title: book.title,
            detailUrl: book.detailUrl,
            host: host,
            snapshot: ExtensionExecutionSnapshot(
                packageId: ext.packageId,
                name: ext.name,
                localPath: ext.localPath,
                downloadUrl: ext.downloadUrl,
                configJson: ext.configJson
            )
        )
    }

    /// Badge cạnh dòng truyện. Dấu chấm thay cho số khi mục lục chỉ lấy được một phần
    /// (`isCountExact == false`) — thà không nói số còn hơn nói số sai.
    @ViewBuilder
    internal func newChapterBadge(for bookId: String) -> some View {
        if let record = newChapters.record(for: bookId), record.hasNew {
            Text(record.badgeText)
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.red))
                .accessibilityLabel(
                    record.isCountExact
                        ? "\(record.newChapterCount) chương mới"
                        : "Có chương mới"
                )
        }
    }

    // MARK: - Ba đường refresh

    /// Lượt tự động lúc mở Kệ sách: dọn record của truyện đã xoá rồi kiểm tra nếu qua cửa cooldown.
    /// Chạy trong `.task` nên **không** chặn khởi động; im lặng khi không có gì mới.
    internal func runAutoNewChapterCheck() async {
        await newChapters.loadIfNeeded()
        await newChapters.prune(keeping: Set(allBooks.map { $0.bookId }))
        let targets = newChapterTargets
        guard !targets.isEmpty else { return }
        guard let summary = await newChapters.autoCheck(targets: targets) else { return }
        showNewChapterSummary(summary, announceEmpty: false)
    }

    /// Refresh tay toàn bộ kệ — bỏ qua cooldown, luôn báo kết quả.
    internal func checkAllNewChapters() {
        let targets = newChapterTargets
        guard !targets.isEmpty else {
            ToastManager.shared.show(message: "Không có truyện online nào trên kệ để kiểm tra")
            return
        }
        Task {
            guard let summary = await newChapters.checkAll(targets: targets) else { return }
            showNewChapterSummary(summary, announceEmpty: true)
        }
    }

    /// Refresh tay một truyện.
    internal func checkNewChapters(for book: Book) {
        guard let target = newChapterTarget(for: book) else {
            ToastManager.shared.show(message: "Truyện này không kiểm tra được chương mới", type: .error)
            return
        }
        Task {
            guard let summary = await newChapters.check(target: target) else { return }
            showNewChapterSummary(summary, announceEmpty: true)
        }
    }

    /// Một lượt = **một** toast, kể cả khi kiểm tra 20 truyện.
    private func showNewChapterSummary(_ summary: NewChapterInboxManager.BatchSummary, announceEmpty: Bool) {
        if summary.bookCount > 0 {
            let prefix = summary.hasInexact ? "ít nhất " : ""
            let message = summary.bookCount == 1
                ? "1 truyện có \(prefix)\(summary.chapterCount) chương mới"
                : "\(summary.bookCount) truyện có \(prefix)\(summary.chapterCount) chương mới"
            ToastManager.shared.show(message: message, type: .success)
            return
        }

        guard announceEmpty else { return }

        if summary.failureCount > 0 && summary.checkedCount == summary.failureCount {
            ToastManager.shared.show(message: "Không kiểm tra được chương mới", type: .error)
        } else {
            ToastManager.shared.show(message: "Không có chương mới")
        }
    }
}
