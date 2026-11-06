import Foundation
import SwiftData
import UIKit

/// Tự sang **phim đề xuất đầu tiên** khi phim hết tập cuối (công tắc `VideoAutoNextPolicy`) — ở mọi nơi: màn xem đang mở,
/// cửa sổ nhỏ, hub, app chạy nền. Sang ngay, không đếm ngược (anh Bửu chọn).
///
/// - **Tải trước**: phiên bắt đầu nạp tập cuối (`VideoPlaybackSession.beginEpisodeLoad`) ⇒ lấy nhóm đề xuất của phim
///   (model của màn xem → cache chi tiết → tải chi tiết, `isInteractive: false`) rồi chạy trang 1 của **nhóm đầu tiên** có
///   script. Đề xuất ở màn xem chỉ tải khi cuộn tới (`VideoWatchSuggestSection`) nên không dựa vào đó được.
/// - **Chọn phim**: mục đầu tiên khác phim vừa hết và chưa phát trong chuỗi tự sang hiện tại (chống A → B → A). Nhóm đề
///   xuất chạy bằng tiện ích của phim ⇒ cùng loại video. Chuỗi bắt đầu lại khi phim vừa hết không phải phim tự sang gần nhất.
/// - **Mở**: màn xem đang hiện đúng phim vừa hết ⇒ đổi màn sang phim mới tại chỗ (`replace(with:autoNext:)`); không có
///   màn (cửa sổ nhỏ, hub, nền) ⇒ dựng `VideoWatchModel` không màn, giữ tới khi nó mở phiên phát (tối đa 90 giây). Cả hai
///   phát luôn dù "Tự phát khi mở phim" tắt, giữ trạng thái tiếng của phim vừa xem, và báo "Tự sang: <tên>" khi phim mới
///   bắt đầu phát (`VideoPlaybackSession.open(startNotice:)`). Lượt tải nằm trong background task: lúc hết phim không còn
///   tiếng giữ app sống khi đang chạy nền.
/// - Phim nhúng trang không báo hết phim ⇒ không tự sang. Phim nhập từ file không có đề xuất.
@MainActor
final class VideoAutoNextCoordinator {
    static let shared = VideoAutoNextCoordinator()

    private static let headlessTimeoutNanoseconds: UInt64 = 90_000_000_000

    /// Model của màn xem đang hiện (`VideoPlayerScreen` báo hiện / ẩn).
    private weak var screenModel: VideoWatchModel?
    /// Phim đã (đang) tải trước đề xuất + lượt tải đó (kết quả = trang 1 của nhóm đề xuất đầu tiên).
    private var preparedBookId: String?
    private var prepareTask: Task<[ExtensionItemResult], Never>?
    /// Phim mở không màn — giữ tới khi nó mở phiên phát hoặc hết hạn.
    private var headlessModel: VideoWatchModel?
    private var headlessTimeoutTask: Task<Void, Never>?
    private var endTask: Task<Void, Never>?
    /// Link chi tiết của các phim trong chuỗi tự sang hiện tại.
    private var chainLinks: Set<String> = []
    /// Phim mở gần nhất bằng tự sang — phim khác hết tập cuối ⇒ chuỗi mới.
    private var lastAutoOpenedBookId: String?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    private init() {}

    // MARK: - Màn xem

    func noteScreen(_ model: VideoWatchModel, isVisible: Bool) {
        if isVisible {
            screenModel = model
        } else if screenModel === model {
            screenModel = nil
        }
    }

    // MARK: - Tải trước

    /// Gọi khi phiên bắt đầu nạp tập cuối (và lúc hết tập cuối, nếu chưa tải). Gọi lặp cho cùng phim thì giữ lượt cũ.
    @discardableResult
    func prepare(for launch: BookContentLaunch) -> Task<[ExtensionItemResult], Never>? {
        guard VideoAutoNextPolicy.isEnabled, !LocalMediaPackage.isLocalMedia(packageId: launch.extensionPackageId) else {
            return nil
        }
        if preparedBookId == launch.bookId, let prepareTask { return prepareTask }
        preparedBookId = launch.bookId
        prepareTask?.cancel()
        let task = Task { [weak self] () -> [ExtensionItemResult] in
            guard let self else { return [] }
            return await self.loadSuggestions(for: launch)
        }
        prepareTask = task
        return task
    }

    private func loadSuggestions(for launch: BookContentLaunch) async -> [ExtensionItemResult] {
        guard let ext = ExtensionLibraryRepository.snapshot(packageId: launch.extensionPackageId), !ext.localPath.isEmpty else {
            AppLogger.shared.log("⚠️ [VideoAutoNext] Tiện ích của phim chưa cài ⇒ không tải đề xuất")
            return []
        }
        let categories = await suggestCategories(for: launch, ext: ext)
        guard let category = categories.first(where: { !$0.script.isEmpty }) else {
            AppLogger.shared.log("⏭️ [VideoAutoNext] Phim không có nhóm đề xuất (bookId=\(launch.bookId))")
            return []
        }
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
            AppLogger.shared.log("⏭️ [VideoAutoNext] Tải sẵn nhóm đề xuất «\(category.title)»: \(results.count) phim")
            return results
        } catch {
            if !(error is CancellationError) {
                AppLogger.shared.log("❌ [VideoAutoNext] Không tải được nhóm đề xuất «\(category.title)»: \(error.localizedDescription)")
            }
            return []
        }
    }

    /// Màn xem đang có chi tiết của phim → cache chi tiết (5 phút) → tải chi tiết không tương tác.
    private func suggestCategories(for launch: BookContentLaunch, ext: Extension) async -> [CategoryResult] {
        if let model = screenModel, model.bookId == launch.bookId, !model.suggests.isEmpty { return model.suggests }
        if let cached = BookDetailCacheManager.shared.getCache(for: launch.bookId), !cached.suggests.isEmpty {
            return cached.suggests
        }
        guard let detailUrl = launch.bookDetailUrl, !detailUrl.isEmpty else { return [] }
        let snapshot = ExtensionExecutionSnapshot(
            packageId: ext.packageId,
            name: ext.name,
            localPath: ext.localPath,
            downloadUrl: ext.downloadUrl,
            configJson: ext.configJson
        )
        let host = ExtensionHostResolver.nonEmpty(launch.host) ?? ext.sourceUrl
        let context = SourceRuntimeContext(bookId: launch.bookId, bookUrl: detailUrl, bookName: launch.bookTitle, isInteractive: false)
        do {
            return try await BookDetailLoader.shared.fetchDetail(snapshot: snapshot, url: detailUrl, host: host, context: context).suggests
        } catch {
            if !(error is CancellationError) {
                AppLogger.shared.log("❌ [VideoAutoNext] Không tải được chi tiết phim để lấy đề xuất: \(error.localizedDescription)")
            }
            return []
        }
    }

    // MARK: - Hết tập cuối

    /// `VideoPlaybackSession` gọi khi item của tập cuối phát hết.
    func lastEpisodeDidEnd(launch: BookContentLaunch, isMuted: Bool, modelContainer: ModelContainer?) {
        guard VideoAutoNextPolicy.isEnabled else { return }
        guard let container = modelContainer ?? screenModel?.modelContainer else {
            AppLogger.shared.log("❌ [VideoAutoNext] Thiếu ModelContainer ⇒ không tự sang được")
            return
        }
        if lastAutoOpenedBookId != launch.bookId { chainLinks = [] }
        if let link = launch.bookDetailUrl, !link.isEmpty { chainLinks.insert(link) }
        guard let task = prepare(for: launch) else { return }
        beginBackgroundTask()
        endTask?.cancel()
        endTask = Task { [weak self] in
            let items = await task.value
            guard let self, !Task.isCancelled else { return }
            if !self.openNext(after: launch, items: items, isMuted: isMuted, container: container) {
                self.endBackgroundTask()
            }
        }
    }

    /// `true` ⇒ đã bắt đầu mở phim mới (background task kết thúc ở `didOpen` / hết hạn).
    private func openNext(after ended: BookContentLaunch, items: [ExtensionItemResult], isMuted: Bool, container: ModelContainer) -> Bool {
        let session = VideoPlaybackSession.shared
        // Trong lúc chờ đề xuất, người dùng đã mở phim khác hoặc bấm xem lại ⇒ thôi.
        guard session.launch?.bookId == ended.bookId, session.reachedEndOfItem else {
            AppLogger.shared.log("⏭️ [VideoAutoNext] Phim đã đổi / đang xem lại ⇒ không tự sang")
            return false
        }
        let endedLink = ended.bookDetailUrl ?? ""
        guard let item = items.first(where: { !$0.link.isEmpty && $0.link != endedLink && !chainLinks.contains($0.link) }) else {
            AppLogger.shared.log("⏭️ [VideoAutoNext] Không còn phim đề xuất chưa phát trong chuỗi ⇒ dừng ở phim này")
            return false
        }
        chainLinks.insert(item.link)
        let request = VideoWatchRequest(
            packageId: ended.extensionPackageId,
            detailUrl: item.link,
            sourceName: ended.bookSourceName ?? "",
            host: item.host,
            title: item.name,
            coverUrl: item.cover
        )
        let start = VideoWatchModel.AutoNextStart(muted: isMuted)
        if let model = screenModel, model.bookId == ended.bookId {
            AppLogger.shared.log("⏭️ [VideoAutoNext] Hết phim ⇒ màn xem đổi sang phim đề xuất «\(item.name)»")
            model.replace(with: request, autoNext: start)
        } else {
            AppLogger.shared.log("⏭️ [VideoAutoNext] Hết phim (không có màn xem) ⇒ mở phim đề xuất «\(item.name)»")
            let model = VideoWatchModel(request: request, modelContainer: container)
            model.autoNext = start
            holdHeadless(model)
            model.start()
        }
        return true
    }

    /// Model (có màn hoặc không) vừa mở phiên phát cho phim tự sang.
    func didOpen(bookId: String) {
        lastAutoOpenedBookId = bookId
        if headlessModel?.bookId == bookId {
            releaseHeadless()
        }
        endBackgroundTask()
    }

    // MARK: - Model không màn

    private func holdHeadless(_ model: VideoWatchModel) {
        releaseHeadless()
        headlessModel = model
        headlessTimeoutTask = Task { [weak self, weak model] in
            try? await Task.sleep(nanoseconds: Self.headlessTimeoutNanoseconds)
            guard !Task.isCancelled, let self, let model, self.headlessModel === model else { return }
            AppLogger.shared.log("❌ [VideoAutoNext] Phim đề xuất không mở được sau 90 giây ⇒ bỏ")
            self.releaseHeadless()
            self.endBackgroundTask()
        }
    }

    private func releaseHeadless() {
        headlessTimeoutTask?.cancel()
        headlessTimeoutTask = nil
        headlessModel?.cancel()
        headlessModel = nil
    }

    // MARK: - Background task

    private func beginBackgroundTask() {
        endBackgroundTask()
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "VideoAutoNext") { [weak self] in
            let owner = self
            MainActor.assumeIsolated {
                owner?.endBackgroundTask()
            }
        }
    }

    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }
}
