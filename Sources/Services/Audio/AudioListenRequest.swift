import Foundation
import SwiftData

/// Dữ liệu lúc bấm mở một album / bài nghe (tiện ích loại `audio`) — đầu vào của `AudioPlaybackSession.open`.
///
/// Như `VideoWatchRequest`: item danh sách (Khám phá, Tìm, Thể loại…) đi `init(packageId:detailUrl:…)`, id album phân
/// giải bằng `resolveBookId(in:)` theo **đúng** quy tắc của phim (`VideoWatchRequest.resolveBookId(matchedBookId:…)` +
/// `VideoWatchRequest.findBook`) — không nhân bản quy tắc; `Book` đã có / router đi `init(book:)` / `init(launch:)`,
/// `knownBookId` là id thật, dùng nguyên.
struct AudioListenRequest: Equatable {
    let packageId: String
    /// Link chi tiết **nguyên văn** như item trả về — so khớp với `Book.detailUrl` cũng nguyên văn.
    let detailUrl: String
    let sourceName: String
    /// Host của item; `nil`/rỗng ⇒ host của `Book` → host chi tiết trả về → `source` của tiện ích.
    let host: String?
    /// Tên / bìa có sẵn ở item danh sách — hiện ngay trong lúc tải chi tiết.
    let title: String?
    let coverUrl: String?
    /// Id của `Book` đã có (Kệ / Lịch sử / router) — dùng nguyên, không tra lại.
    let knownBookId: String?
    /// Bài muốn phát (chỉ số mục lục); `nil` = bài đang nghe dở, chưa nghe thì bài đầu.
    let trackIndex: Int?
    /// Giây muốn tua tới ở `trackIndex`; `nil` = giây đã lưu khi `trackIndex` trùng bài nghe dở, khác thì từ đầu.
    let initialSeconds: Int?
    /// Khác `nil` (kể cả rỗng) = lượt mở của `PlaylistPlaybackCoordinator`: bài phải đúng mục playlist — link bài này trước,
    /// `trackIndex` sau; album không còn bài đó ⇒ báo lỗi (coordinator bỏ qua), không phát bài khác.
    let playlistTrackUrl: String?

    init(
        packageId: String,
        detailUrl: String,
        sourceName: String,
        host: String? = nil,
        title: String? = nil,
        coverUrl: String? = nil,
        knownBookId: String? = nil,
        trackIndex: Int? = nil,
        initialSeconds: Int? = nil,
        playlistTrackUrl: String? = nil
    ) {
        self.packageId = packageId
        self.detailUrl = detailUrl
        self.sourceName = sourceName
        self.host = host
        self.title = title
        self.coverUrl = coverUrl
        self.knownBookId = knownBookId
        self.trackIndex = trackIndex
        self.initialSeconds = initialSeconds
        self.playlistTrackUrl = playlistTrackUrl
    }

    /// Album đã có `Book` (Kệ, Lịch sử, Bộ sưu tập…): mở đúng `Book` được bấm, tiếp bài + giây đang nghe dở.
    init(book: Book) {
        self.init(
            packageId: book.extensionPackageId,
            detailUrl: book.detailUrl,
            sourceName: book.sourceName,
            host: book.host,
            title: book.title,
            coverUrl: book.coverUrl,
            knownBookId: book.bookId
        )
    }

    /// Từ router (`BookContentDestination`): `chapterIndex` = bài; `initialParagraphIndex` của âm thanh là **số giây** —
    /// `nil` ⇒ giây đã lưu (khi trùng bài nghe dở), âm (`-1` của Chi tiết = "đầu chương") ⇒ từ đầu bài.
    init(launch: BookContentLaunch) {
        self.init(
            packageId: launch.extensionPackageId,
            detailUrl: launch.bookDetailUrl ?? "",
            sourceName: launch.bookSourceName ?? "",
            host: launch.host,
            title: launch.bookTitle,
            coverUrl: launch.bookCoverUrl,
            knownBookId: launch.bookId,
            trackIndex: launch.chapterIndex,
            initialSeconds: launch.initialParagraphIndex.map { max(0, $0) }
        )
    }

    // MARK: - Định danh

    /// Id album cho lượt mở này. Gọi **trước** mọi lần gọi nguồn (cache chi tiết, mục lục, tiến độ đều khoá theo id).
    /// Rỗng khi thiếu cả tiện ích lẫn link (caller tự cấp id tạm).
    @MainActor
    func resolveBookId(in context: ModelContext) -> String {
        if let knownBookId, !knownBookId.isEmpty { return knownBookId }
        let matched = VideoWatchRequest.findBook(packageId: packageId, detailUrl: detailUrl, in: context)?.bookId
        return VideoWatchRequest.resolveBookId(
            matchedBookId: matched,
            preferredBookId: nil,
            packageId: packageId,
            detailUrl: detailUrl,
            bookExists: { _ in false }
        )
    }
}
