import Foundation

/// Phát **bản tải** của tập (`VideoOfflineStore`) và các thao tác tải / xoá bản tải từ trình phát.
///
/// - `runEpisodeLoad` (`+Loading`) gọi `startOfflinePlaybackIfAvailable` **trước** khi tra tiện ích / server: tập có
///   manifest khớp URL tập ⇒ phát ngay, không cần mạng (tiện ích đã gỡ vẫn xem được). HLS phát qua
///   `VideoOfflineHTTPServer` (127.0.0.1), file đơn phát `file://`; phụ đề viết thẳng từ file, mốc "Bỏ qua" từ manifest.
/// - Chip "Trực tuyến" (`playOnline`) ⇒ nạp server như thường cho đúng tập đó; chip "Bản tải" (`playOffline`) quay lại.
///   Đổi tập thì bỏ lựa chọn trực tuyến (tập đã tải lại ưu tiên bản tải).
/// - Bản tải không kiểm tiếng, không có phương án dự phòng (`sourceResolution == nil`). Mỗi lượt nạp HLS bật server mới
///   (listener có thể đã chết khi app bị treo nền); item lỗi ⇒ nạp lại tại vị trí đang xem, tối đa một lần mỗi
///   `offlineRetryWindow` giây.
/// - Toast thuộc tầng View: các hàm tải / xoá trả kết quả để màn hình tự báo.
extension VideoPlaybackSession {
    enum EpisodeDownloadRequest {
        case queued
        case alreadyQueued
        case alreadyDownloaded
        /// Chưa có hàng `Book` trong CSDL (hiếm — phim mở lần đầu chưa kịp tạo sách lịch sử).
        case unavailable
    }

    /// Khoảng tối thiểu giữa hai lần tự nạp lại bản tải sau lỗi phát.
    static let offlineRetryWindow: TimeInterval = 20

    /// Hàng chip / menu server có gì để chọn (bản tải và/hoặc nhiều server). Phim nhập từ file thì không: chỉ có bản trên
    /// máy, "Trực tuyến" không có nguồn để nạp.
    var hasSourceChoices: Bool {
        !isLocalMedia && (hasOfflineCopy || servers.count > 1)
    }

    /// Phim nhập từ file (`LocalMediaPackage`): bản trên máy là bản **duy nhất** ⇒ ẩn chip "Bản tải"/"Trực tuyến", mọi
    /// lối tải tập / xoá bản tải.
    var isLocalMedia: Bool {
        LocalMediaPackage.isLocalMedia(packageId: launch?.extensionPackageId)
    }

    // MARK: - Phát

    /// `true` khi đã nhận phát tập này bằng bản tải (hoặc lượt nạp đã bị lượt mới thay) — caller dừng pipeline online.
    func startOfflinePlaybackIfAvailable(_ episode: Episode, generation: Int) async -> Bool {
        guard let bookId = launch?.bookId else { return false }
        // Menu tải / xoá của trình phát đọc `VideoOfflineLibrary` ⇒ làm mới tóm tắt mỗi lượt nạp tập.
        VideoOfflineLibrary.shared.refresh(bookId: bookId)
        if onlineOverrideEpisodeIndex != episode.index { onlineOverrideEpisodeIndex = nil }
        guard let manifest = offlineManifest(for: episode, bookId: bookId) else {
            hasOfflineCopy = false
            return false
        }
        hasOfflineCopy = true
        guard onlineOverrideEpisodeIndex == nil else { return false }

        phase = .resolving
        if manifest.kind == .hls {
            // App bị treo nền có thể làm listener chết mà vẫn tưởng còn sống ⇒ mỗi lượt nạp bật server mới (queue nối
            // tiếp: tắt xong mới bật). Item cũ đã gỡ ở `prepareForNewLoad`.
            VideoOfflineHTTPServer.shared.stop()
        }
        let url = await offlineURL(manifest, bookId: bookId, episodeIndex: episode.index)
        guard isCurrent(generation) else { return true }
        guard let url else {
            AppLogger.shared.log("❌ [VideoOffline] Không mở được bản tải tập \(episode.index) (\(manifest.kind.rawValue)) ⇒ phát trực tuyến")
            return false
        }
        let track = VideoTrack(
            kind: .native,
            data: url.absoluteString,
            timeSkips: manifest.timeSkips.map { VideoTimeSkip(fromMs: $0.fromMs, toMs: $0.toMs) },
            subtitles: offlineSubtitles(manifest, bookId: bookId, episodeIndex: episode.index)
        )
        isPlayingOffline = true
        let quality = manifest.qualityLabel.isEmpty ? "" : ", \(manifest.qualityLabel)"
        AppLogger.shared.log("📥 [VideoOffline] Phát bản tải tập \(episode.index) (\(manifest.kind.rawValue)\(quality))")
        apply(plan: .native(url: url, headers: [:]), track: track, generation: generation)
        return true
    }

    /// Chip "Trực tuyến": xem tập đang mở bằng server dù đã có bản tải.
    func playOnline() {
        guard launch != nil, let episode = currentEpisode else { return }
        onlineOverrideEpisodeIndex = episode.index
        beginUserRequestedPlayback()
        beginEpisodeLoad(episode.index, resumeSeconds: resumePointForReload())
    }

    /// Chip "Bản tải": quay lại bản trên máy.
    func playOffline() {
        guard launch != nil, hasOfflineCopy, let episode = currentEpisode else { return }
        if isPlayingOffline { return }
        onlineOverrideEpisodeIndex = nil
        beginUserRequestedPlayback()
        beginEpisodeLoad(episode.index, resumeSeconds: resumePointForReload())
    }

    /// Gọi đầu `logItemFailureAndTryFallback`: bản tải lỗi ⇒ dựng lại server + nạp lại, trả `true`. Lần thử trước còn
    /// trong `offlineRetryWindow` giây thì thôi (tránh vòng lặp) — báo lỗi để người dùng chọn "Tải lại"/"Trực tuyến".
    func retryOfflineAfterFailure(message: String) -> Bool {
        guard isPlayingOffline, let episode = currentEpisode else { return false }
        let now = ProcessInfo.processInfo.systemUptime
        if let last = offlineLastRetryUptime, now - last < Self.offlineRetryWindow { return false }
        offlineLastRetryUptime = now
        AppLogger.shared.log("❌ [VideoOffline] Bản tải tập \(episode.index) lỗi khi phát: \(message) ⇒ bật lại server, nạp lại")
        VideoOfflineHTTPServer.shared.stop()
        beginEpisodeLoad(episode.index, resumeSeconds: resumePointForReload())
        return true
    }

    /// Gọi trong `stop()` (`resetPlaybackState`).
    func resetOfflineState() {
        hasOfflineCopy = false
        isPlayingOffline = false
        onlineOverrideEpisodeIndex = nil
        offlineLastRetryUptime = nil
        VideoOfflineHTTPServer.shared.stop()
    }

    // MARK: - Tải / xoá từ trình phát

    func requestEpisodeDownload(_ episode: Episode) -> EpisodeDownloadRequest {
        guard !episode.isSection, let container = modelContainer, let book = fetchBook() else { return .unavailable }
        switch DownloadManager.shared.enqueueVideoEpisode(book: book, episodeIndex: episode.index, container: container) {
        case .queued: return .queued
        case .alreadyQueued: return .alreadyQueued
        case .alreadyDownloaded: return .alreadyDownloaded
        }
    }

    /// Xoá bản tải một tập. Đang phát đúng bản đó ⇒ chuyển sang trực tuyến trước (server đang đọc file).
    func deleteEpisodeDownload(_ episode: Episode) async throws {
        guard let bookId = launch?.bookId else { return }
        let library = VideoOfflineLibrary.shared
        guard !library.isDownloading(bookId: bookId, episodeIndex: episode.index) else {
            throw VideoOfflineLibrary.DeleteError.episodeDownloading
        }
        if episode.index == currentEpisodeIndex, isPlayingOffline {
            playOnline()
        }
        try await library.deleteEpisode(bookId: bookId, episodeIndex: episode.index)
        if episode.index == currentEpisodeIndex {
            hasOfflineCopy = false
            onlineOverrideEpisodeIndex = nil
        }
    }

    // MARK: - Nội bộ

    /// Manifest của tập nếu khớp URL tập trong mục lục (nguồn đổi đường dẫn ⇒ coi như chưa tải).
    private func offlineManifest(for episode: Episode, bookId: String) -> VideoEpisodeManifest? {
        guard let manifest = VideoOfflineStore.manifest(bookId: bookId, episodeIndex: episode.index) else { return nil }
        guard manifest.episodeUrl == episode.url else {
            AppLogger.shared.log("⚠️ [VideoOffline] Bản tải tập \(episode.index) không khớp URL tập hiện tại — phát trực tuyến")
            return nil
        }
        return manifest
    }

    private func offlineURL(_ manifest: VideoEpisodeManifest, bookId: String, episodeIndex: Int) async -> URL? {
        let entry = VideoOfflineStore.fileURL(bookId: bookId, episodeIndex: episodeIndex, file: manifest.entryFile)
        guard FileManager.default.fileExists(atPath: entry.path) else { return nil }
        switch manifest.kind {
        case .file:
            return entry
        case .hls:
            let path = VideoOfflineStore.relativePath(bookId: bookId, episodeIndex: episodeIndex, file: manifest.entryFile)
            return await VideoOfflineHTTPServer.shared.url(forRelativePath: path)
        }
    }

    /// Phụ đề đầu tiên đọc từ file, đưa vào dạng "nội dung viết thẳng" của `VideoSubtitleParser`.
    private func offlineSubtitles(_ manifest: VideoEpisodeManifest, bookId: String, episodeIndex: Int) -> [VideoSubtitleTrack] {
        guard let subtitle = manifest.subtitles.first else { return [] }
        let url = VideoOfflineStore.fileURL(bookId: bookId, episodeIndex: episodeIndex, file: subtitle.file)
        guard let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8), !text.isEmpty else {
            AppLogger.shared.log("❌ [VideoOffline] Không đọc được phụ đề đã tải của tập \(episodeIndex)")
            return []
        }
        return [VideoSubtitleTrack(data: text, label: subtitle.label, language: subtitle.language)]
    }
}
