import Foundation
import SwiftData

/// Dữ liệu lúc bấm mở một phim — đầu vào của `VideoWatchModel` / `VideoWatchPresenter`.
///
/// Hai kiểu lối vào:
/// - Item danh sách (Khám phá, Tìm, Thể loại, Đề xuất…): `init(packageId:detailUrl:…)`. Id phim **không** lấy từ caller
///   (mỗi màn danh sách tự chế một kiểu: link, `tên_link`…) mà phân giải bằng `resolveBookId(in:)`.
/// - `Book` đã có / router (`init(book:)`, `init(launch:)`): `knownBookId` là id thật, dùng nguyên.
///
/// **Quy tắc định danh duy nhất** (`resolveBookId(matchedBookId:preferredBookId:…)`, dùng chung với
/// `BookDetailView.resolveBookId`): `Book` cùng (link chi tiết, tiện ích) ⇒ id đó; id caller đưa vào là id của một `Book`
/// có thật ⇒ giữ; còn lại ⇒ id **xác định** `BookIdUtils.make(...)`. Nhờ vậy mở cùng một phim từ Khám phá rồi từ Tìm
/// (trước khi có `Book`) vẫn ra cùng một id ⇒ không sinh hai `Book` ở Lịch sử, và tiến độ / server đã nhớ / bản tải /
/// trạng thái nguồn Legado (đều khoá theo id) không lệch nhau.
struct VideoWatchRequest: Equatable {
    let packageId: String
    /// Link chi tiết **nguyên văn** như item trả về — so khớp với `Book.detailUrl` cũng nguyên văn, không chuẩn hoá.
    let detailUrl: String
    let sourceName: String
    /// Host của item (`item.host`); `nil`/rỗng ⇒ host của `Book` → host chi tiết trả về → `source` của tiện ích.
    let host: String?
    /// Tên / bìa có sẵn ở item danh sách — hiện ngay trong lúc tải chi tiết.
    let title: String?
    let coverUrl: String?
    /// Id của `Book` đã có (mở từ Kệ / Lịch sử / router) — dùng nguyên, không tra lại.
    let knownBookId: String?
    /// Tập muốn mở (chỉ số mục lục); `nil` = tập đang xem dở, chưa xem thì tập đầu.
    let episodeIndex: Int?
    /// Giây muốn tua tới ở `episodeIndex`; `nil` = giây đã lưu.
    let initialSeconds: Int?

    init(
        packageId: String,
        detailUrl: String,
        sourceName: String,
        host: String? = nil,
        title: String? = nil,
        coverUrl: String? = nil,
        knownBookId: String? = nil,
        episodeIndex: Int? = nil,
        initialSeconds: Int? = nil
    ) {
        self.packageId = packageId
        self.detailUrl = detailUrl
        self.sourceName = sourceName
        self.host = host
        self.title = title
        self.coverUrl = coverUrl
        self.knownBookId = knownBookId
        self.episodeIndex = episodeIndex
        self.initialSeconds = initialSeconds
    }

    /// Phim đã có `Book` (Kệ, Lịch sử, Bộ sưu tập…): mở đúng `Book` được bấm, kể cả khi còn bản trùng link cũ.
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

    /// Từ router (`BookContentDestination`): id của launch là id mà phiên phát dùng. `initialParagraphIndex` của video là
    /// **số giây**; âm (Chi tiết truyền `-1`) ⇒ coi như không chỉ định.
    init(launch: BookContentLaunch) {
        let seconds = launch.initialParagraphIndex.flatMap { $0 >= 0 ? $0 : nil }
        self.init(
            packageId: launch.extensionPackageId,
            detailUrl: launch.bookDetailUrl ?? "",
            sourceName: launch.bookSourceName ?? "",
            host: launch.host,
            title: launch.bookTitle,
            coverUrl: launch.bookCoverUrl,
            knownBookId: launch.bookId,
            episodeIndex: launch.chapterIndex,
            initialSeconds: seconds
        )
    }

    // MARK: - Định danh

    /// Id phim cho lượt mở này. Gọi **trước** mọi lần gọi nguồn: `SourceRuntimeContext.bookId`, cache chi tiết và mọi kho
    /// theo id đều phải dùng đúng id này.
    @MainActor
    func resolveBookId(in context: ModelContext) -> String {
        if let knownBookId, !knownBookId.isEmpty { return knownBookId }
        let matched = Self.findBook(packageId: packageId, detailUrl: detailUrl, in: context)?.bookId
        return Self.resolveBookId(
            matchedBookId: matched,
            preferredBookId: nil,
            packageId: packageId,
            detailUrl: detailUrl,
            bookExists: { _ in false }
        )
    }

    /// Quy tắc dùng chung (màn xem phim + `BookDetailView`):
    /// 1. `matchedBookId` — `Book` cùng (link, tiện ích) do caller tra (Chi tiết dùng `localBook` của nó);
    /// 2. `preferredBookId` khi `bookExists` xác nhận là id của một `Book` có thật;
    /// 3. id xác định `BookIdUtils.make(...)`. Tiện ích và link đều rỗng (`make` trả `""`) ⇒ `preferredBookId`.
    static func resolveBookId(
        matchedBookId: String?,
        preferredBookId: String?,
        packageId: String,
        detailUrl: String,
        bookExists: (String) -> Bool
    ) -> String {
        if let matchedBookId, !matchedBookId.isEmpty { return matchedBookId }
        if let preferredBookId, !preferredBookId.isEmpty, bookExists(preferredBookId) { return preferredBookId }
        let made = BookIdUtils.make(extensionPackageId: packageId, detailUrl: detailUrl)
        return made.isEmpty ? (preferredBookId ?? "") : made
    }

    /// `Book` cùng tiện ích + cùng link chi tiết (khớp như `BookDetailView.localBook`); nhiều bản (đổi nguồn nhiều lần
    /// trước 1.3.689) ⇒ bản xem gần nhất, như `BookSourceChangeCoordinator.findBook`. Predicate chỉ **một** điều kiện
    /// bằng chuỗi, điều kiện tiện ích lọc trên RAM (bộ dịch predicate SQLite iOS 17 lỗi với điều kiện chuỗi phức tạp).
    @MainActor
    static func findBook(packageId: String, detailUrl: String, in context: ModelContext) -> Book? {
        guard !detailUrl.isEmpty else { return nil }
        let targetUrl = detailUrl
        let descriptor = FetchDescriptor<Book>(predicate: #Predicate<Book> { $0.detailUrl == targetUrl })
        let books = (try? context.fetch(descriptor)) ?? []
        return books
            .filter { $0.extensionPackageId == packageId }
            .max { $0.lastReadDate < $1.lastReadDate }
    }
}
