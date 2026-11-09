import Foundation

/// Gợi ý của album đang mở trong trình nghe — **một nguồn** cho cả tự phát (`AudioAutoNextCoordinator`, chỉ cần nhóm
/// đầu) lẫn phần "gợi ý" ở trang Danh sách của màn nghe (`AudioSuggestionSection`, hiện tới `maxGroups` nhóm).
///
/// - **Nhóm gợi ý** = `suggests` của chi tiết album: chờ chi tiết trình nghe đang tải (khỏi tải trùng) → cache chi tiết
///   (`BookDetailCacheManager`, `AudioPlaybackSession.apply(detail:)` ghi) → tải chi tiết không tương tác. Mỗi nhóm có
///   `script` chạy **trang 1** một lần; nhóm rỗng / lỗi bị bỏ.
/// - Giữ kết quả của **một** album (`bookId`): gọi lại cho cùng album dùng lượt / kết quả cũ, không gọi nguồn lặp lại;
///   album khác ⇒ huỷ lượt cũ, tải lại từ đầu.
/// - Nhóm đầu tải trước (tự phát cần nó); các nhóm sau chỉ tải khi màn nghe cần hiện (`loadForDisplay`).
/// - View chỉ đọc `bookId` / `groups` (`@Observable`); chỉ khớp album đang phát khi `bookId == session.bookId`.
@MainActor
@Observable
final class AudioSuggestionStore {
    static let shared = AudioSuggestionStore()

    /// Số nhóm gợi ý tối đa hiện ở trang Danh sách.
    static let maxGroups = 3

    /// Album của một lượt — chụp lúc gọi (session có thể đã đổi album khi gợi ý về).
    struct Album {
        let bookId: String
        let packageId: String
        let detailUrl: String
        let sourceName: String
        let host: String
        let title: String

        /// `nil` khi trình nghe rảnh. (Kiểu lồng không thừa hưởng `@MainActor` của class ⇒ ghi rõ.)
        @MainActor
        static func snapshot(of session: AudioPlaybackSession) -> Album? {
            guard session.isActive, let request = session.request, !session.bookId.isEmpty else { return nil }
            return Album(
                bookId: session.bookId,
                packageId: session.packageId,
                detailUrl: request.detailUrl,
                sourceName: request.sourceName,
                host: ExtensionHostResolver.nonEmpty(session.bookHost) ?? request.host ?? "",
                title: session.albumTitle
            )
        }
    }

    struct SuggestionGroup: Identifiable {
        /// Vị trí của nhóm trong `suggests` (nhóm 0 = nhóm tự phát dùng).
        let id: Int
        let title: String
        let items: [ExtensionItemResult]
    }

    /// Album của `groups` (rỗng = chưa tải gì).
    private(set) var bookId = ""
    /// Các nhóm đã tải xong, theo thứ tự `suggests`; nhóm đầu (id 0) nếu có luôn đứng đầu.
    private(set) var groups: [SuggestionGroup] = []

    @ObservationIgnored private var album: Album?
    @ObservationIgnored private var ext: Extension?
    @ObservationIgnored private var categories: [CategoryResult] = []
    @ObservationIgnored private var firstTask: Task<[ExtensionItemResult], Never>?
    @ObservationIgnored private var firstDone = false
    @ObservationIgnored private var restTask: Task<Void, Never>?
    @ObservationIgnored private var wantsAllGroups = false

    private init() {}

    // MARK: - API

    /// Mục của nhóm gợi ý đầu (tự phát). Cùng album ⇒ dùng lượt / kết quả cũ.
    func firstGroupItems(for album: Album) -> Task<[ExtensionItemResult], Never> {
        if album.bookId == bookId, let firstTask { return firstTask }
        begin(album)
        let task = Task { [weak self] () async -> [ExtensionItemResult] in
            guard let self else { return [] }
            return await self.loadFirstGroup(album)
        }
        firstTask = task
        return task
    }

    /// Bỏ kết quả của album rồi tải lại nhóm đầu (tự phát thử lại khi lượt trước rỗng). Trang Danh sách đang cần mọi nhóm
    /// thì lượt mới tải tiếp các nhóm sau.
    func reloadFirstGroup(for album: Album) -> Task<[ExtensionItemResult], Never> {
        let keepsAll = wantsAllGroups && album.bookId == bookId
        bookId = ""
        let task = firstGroupItems(for: album)
        wantsAllGroups = keepsAll
        return task
    }

    /// Trang Danh sách hiện: tải nhóm đầu (nếu chưa) rồi các nhóm sau, tới `maxGroups`.
    func loadForDisplay(_ album: Album) {
        guard !LocalMediaPackage.isLocalMedia(packageId: album.packageId) else { return }
        _ = firstGroupItems(for: album)
        wantsAllGroups = true
        if firstDone { startRemainingGroups() }
    }

    // MARK: - Tải

    private func begin(_ album: Album) {
        firstTask?.cancel()
        restTask?.cancel()
        firstTask = nil
        restTask = nil
        self.album = album
        bookId = album.bookId
        groups = []
        categories = []
        ext = nil
        firstDone = false
        wantsAllGroups = false
    }

    private func isCurrent(_ album: Album) -> Bool {
        bookId == album.bookId && self.album?.detailUrl == album.detailUrl
    }

    private func loadFirstGroup(_ album: Album) async -> [ExtensionItemResult] {
        guard let ext = ExtensionLibraryRepository.snapshot(packageId: album.packageId), !ext.localPath.isEmpty else {
            AppLogger.shared.log("⚠️ [AudioSuggest] Tiện ích của album chưa cài ⇒ không tải gợi ý")
            markFirstDone(album)
            return []
        }
        let found = await Self.suggestCategories(for: album, ext: ext).filter { !$0.script.isEmpty }
        guard isCurrent(album), !Task.isCancelled else { return [] }
        self.ext = ext
        categories = Array(found.prefix(Self.maxGroups))
        guard let first = categories.first else {
            AppLogger.shared.log("⏭️ [AudioSuggest] Album không có nhóm gợi ý (bookId=\(album.bookId))")
            markFirstDone(album)
            return []
        }
        let items = await Self.runGroup(first, ext: ext)
        guard isCurrent(album), !Task.isCancelled else { return items }
        if !items.isEmpty {
            groups.insert(SuggestionGroup(id: 0, title: first.title, items: items), at: 0)
        }
        markFirstDone(album)
        return items
    }

    private func markFirstDone(_ album: Album) {
        guard isCurrent(album) else { return }
        firstDone = true
        if wantsAllGroups { startRemainingGroups() }
    }

    /// Các nhóm sau nhóm đầu, lần lượt (cùng tiện ích, một lượt mỗi nhóm).
    private func startRemainingGroups() {
        guard restTask == nil, let album, let ext, categories.count > 1 else { return }
        let remaining = Array(categories.enumerated().dropFirst())
        restTask = Task { [weak self] in
            for (offset, category) in remaining {
                let items = await Self.runGroup(category, ext: ext)
                guard let self, !Task.isCancelled, self.isCurrent(album) else { return }
                if !items.isEmpty {
                    self.groups.append(SuggestionGroup(id: offset, title: category.title, items: items))
                }
            }
        }
    }

    /// Chi tiết trình nghe đang tải (chờ nó ghi cache thay vì tải trùng — album một bài tải gợi ý ngay lúc mở) → cache chi
    /// tiết (5 phút) → tải chi tiết không tương tác.
    private static func suggestCategories(for album: Album, ext: Extension) async -> [CategoryResult] {
        let session = AudioPlaybackSession.shared
        if session.bookId == album.bookId, let detailTask = session.detailTask {
            await detailTask.value
        }
        if let cached = BookDetailCacheManager.shared.getCache(for: album.bookId), !cached.suggests.isEmpty {
            return cached.suggests
        }
        guard !album.detailUrl.isEmpty else { return [] }
        let snapshot = ExtensionExecutionSnapshot(
            packageId: ext.packageId,
            name: ext.name,
            localPath: ext.localPath,
            downloadUrl: ext.downloadUrl,
            configJson: ext.configJson
        )
        let host = ExtensionHostResolver.nonEmpty(album.host) ?? ext.sourceUrl
        let bookName = album.title.isEmpty ? nil : album.title
        let context = SourceRuntimeContext(bookId: album.bookId, bookUrl: album.detailUrl, bookName: bookName, isInteractive: false)
        do {
            return try await BookDetailLoader.shared.fetchDetail(snapshot: snapshot, url: album.detailUrl, host: host, context: context).suggests
        } catch {
            if !AudioPlaybackSession.isCancellation(error) {
                AppLogger.shared.log("❌ [AudioSuggest] Không tải được chi tiết album để lấy gợi ý: \(error.localizedDescription)")
            }
            return []
        }
    }

    /// Trang 1 của một nhóm; bỏ mục không tên / không link.
    private static func runGroup(_ category: CategoryResult, ext: Extension) async -> [ExtensionItemResult] {
        do {
            let (results, _) = try await SourceRuntime.shared.executeCustomScript(
                localPath: ext.localPath,
                downloadUrl: ext.downloadUrl,
                scriptFileName: category.script,
                input: category.input,
                page: 1,
                pageUrl: nil,
                configJson: ext.configJson
            )
            let items = results.filter { !$0.link.isEmpty && !$0.name.isEmpty }
            AppLogger.shared.log("⏭️ [AudioSuggest] Tải nhóm gợi ý «\(category.title)»: \(items.count) mục")
            return items
        } catch {
            if !AudioPlaybackSession.isCancellation(error) {
                AppLogger.shared.log("❌ [AudioSuggest] Không tải được nhóm gợi ý «\(category.title)»: \(error.localizedDescription)")
            }
            return []
        }
    }
}
