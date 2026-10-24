import Foundation

/// Tải trọn **một tập phim**: server (server đã nhớ trước, lỗi thì lần lượt server khác) → `track` →
/// `VideoSourceResolver` → phương án tải được đầu tiên (bỏ `.embed`) → `VideoHLSDownloader` / `VideoFileDownloader` →
/// phụ đề đầu tiên → `manifest.json` (sau cùng).
///
/// - Không bao giờ bật màn hình: `SourceRuntimeContext.isInteractive = false`, không bọc `SourceRuntime.userInitiated`.
/// - Link bị từ chối (401/403/404/410 — token hết hạn giữa chừng) ⇒ phân giải lại link của server đó **một** lần rồi tải
///   tiếp bản dở (chữ ký nguồn bỏ query nên khớp lại được).
/// - Media không đi qua pipeline text; `server.data` truyền nguyên văn cho `track`.
struct VideoEpisodeDownloadPipeline {
    enum PipelineError: LocalizedError {
        case noServer
        case embedOnly
        case unreachable

        var errorDescription: String? {
            switch self {
            case .noServer: return "Tập này không có server phát nào."
            case .embedOnly: return "Tập này chỉ xem được dạng nhúng trang, không tải về được."
            case .unreachable: return "Không mở được link video."
            }
        }
    }

    let bookId: String
    let bookTitle: String
    let bookUrl: String?
    let bookHost: String?
    let ext: Extension
    let quality: VideoDownloadQuality
    let rememberedServerTitle: String?
    let client: VideoOfflineHTTPClient
    /// `(phần đã xong 0…1, số byte)` của tập đang tải — gọi từ thread nền.
    let progress: (Double, Int64) -> Void

    func run(_ episode: StoredChapterSnapshot) async throws -> VideoEpisodeManifest {
        let host = ExtensionHostResolver.chapterHost(chapterHost: episode.host, bookHost: bookHost, packageId: ext.packageId)
        let servers = try await SourceRuntime.shared.videoServers(
            localPath: ext.localPath,
            downloadUrl: ext.downloadUrl,
            url: episode.url,
            host: host,
            configJson: ext.configJson,
            context: SourceRuntimeContext(bookId: bookId, bookUrl: bookUrl, bookName: bookTitle,
                                          chapterTitle: episode.title, chapterIndex: episode.index,
                                          isInteractive: false)
        )
        guard !servers.isEmpty else { throw PipelineError.noServer }
        let ordered = orderedServers(servers)
        let directory = try VideoOfflineStore.prepareEpisodeDirectory(bookId: bookId, episodeIndex: episode.index)

        var lastError: Error = PipelineError.noServer
        for (position, server) in ordered.enumerated() {
            try Task.checkCancellation()
            do {
                return try await download(episode, server: server, directory: directory)
            } catch {
                if error is CancellationError || Task.isCancelled { throw CancellationError() }
                lastError = error
                let next = position + 1 < ordered.count ? " — thử server khác" : ""
                AppLogger.shared.log("❌ [VideoOffline] Tập \(episode.index) server «\(server.title)» lỗi: \(error.localizedDescription)\(next)")
            }
        }
        throw lastError
    }

    // MARK: - Một server

    private func download(_ episode: StoredChapterSnapshot, server: VideoServer, directory: URL) async throws -> VideoEpisodeManifest {
        var didReResolve = false
        while true {
            let track = try await SourceRuntime.shared.videoTrack(
                localPath: ext.localPath,
                downloadUrl: ext.downloadUrl,
                data: server.data,
                configJson: ext.configJson
            )
            let resolution = try await Self.resolve(track, packageId: ext.packageId, localPath: ext.localPath)
            let attempts = ([resolution.current] + resolution.fallbacks).filter {
                if case .embed = $0.plan { return false }
                return true
            }
            guard !attempts.isEmpty else { throw PipelineError.embedOnly }

            var lastError: Error = PipelineError.embedOnly
            var linkRejected = false
            for attempt in attempts {
                do {
                    return try await downloadAttempt(attempt.plan, track: track, episode: episode, server: server, directory: directory)
                } catch {
                    if error is CancellationError || Task.isCancelled { throw CancellationError() }
                    lastError = error
                    if let clientError = error as? VideoOfflineHTTPClient.ClientError,
                       case .linkRejected = clientError {
                        linkRejected = true
                    }
                    AppLogger.shared.log("❌ [VideoOffline] Phương án \(attempt.origin.label)\(attempt.note.map { " [\($0)]" } ?? "") lỗi: \(error.localizedDescription)")
                }
            }
            guard linkRejected, !didReResolve else { throw lastError }
            didReResolve = true
            AppLogger.shared.log("📥 [VideoOffline] Link bị từ chối — phân giải lại link server «\(server.title)» rồi tải tiếp")
        }
    }

    private func downloadAttempt(
        _ plan: VideoPlaybackPlan,
        track: VideoTrack,
        episode: StoredChapterSnapshot,
        server: VideoServer,
        directory: URL
    ) async throws -> VideoEpisodeManifest {
        let media = try await downloadMedia(plan, track: track, directory: directory)
        let subtitles = await downloadSubtitle(track, directory: directory)
        let totalBytes = media.totalBytes + subtitles.bytes
        let kind = media.kind
        let segmentCount = media.segmentCount
        let qualityLabel = media.qualityLabel
        let manifest = VideoEpisodeManifest(
            version: VideoEpisodeManifest.currentVersion,
            episodeUrl: episode.url,
            episodeTitle: episode.title,
            serverTitle: server.title,
            kind: kind,
            entryFile: media.entryFile,
            qualityLabel: qualityLabel,
            totalBytes: totalBytes,
            segmentCount: segmentCount,
            subtitles: subtitles.entries,
            timeSkips: track.timeSkips.map { VideoEpisodeManifest.TimeSkip(fromMs: $0.fromMs, toMs: $0.toMs) },
            completedAt: Date()
        )
        try Task.checkCancellation()
        try VideoOfflineStore.saveManifest(manifest, bookId: bookId, episodeIndex: episode.index)
        AppLogger.shared.log("✅ [VideoOffline] Đã tải tập \(episode.index) (\(kind.rawValue), \(segmentCount) đoạn, \(totalBytes / 1_048_576) MB\(qualityLabel.isEmpty ? "" : ", \(qualityLabel)"))")
        return manifest
    }

    private struct MediaOutcome {
        let kind: VideoEpisodeManifest.Kind
        let entryFile: String
        let totalBytes: Int64
        let segmentCount: Int
        let qualityLabel: String
    }

    private func downloadMedia(_ plan: VideoPlaybackPlan, track: VideoTrack, directory: URL) async throws -> MediaOutcome {
        switch plan {
        case .native(let url, let headers):
            if try await Self.isHLS(url: url, mimeType: track.mimeType, headers: headers) {
                let outcome = try await hlsDownloader(headers: headers, subPlaylists: [:]).download(.remote(url), into: directory)
                return MediaOutcome(kind: .hls, entryFile: outcome.entryFile, totalBytes: outcome.totalBytes,
                                    segmentCount: outcome.segmentCount, qualityLabel: outcome.qualityLabel)
            }
            let outcome = try await VideoFileDownloader(progress: progress).download(url: url, headers: headers, into: directory)
            return MediaOutcome(kind: .file, entryFile: outcome.fileName, totalBytes: outcome.totalBytes,
                                segmentCount: 1, qualityLabel: "")
        case .hlsText(let playlist, let baseURL, let headers, let subPlaylists):
            let outcome = try await hlsDownloader(headers: headers, subPlaylists: subPlaylists)
                .download(.text(playlist, baseURL: baseURL), into: directory)
            return MediaOutcome(kind: .hls, entryFile: outcome.entryFile, totalBytes: outcome.totalBytes,
                                segmentCount: outcome.segmentCount, qualityLabel: outcome.qualityLabel)
        case .embed:
            throw PipelineError.embedOnly
        }
    }

    private func hlsDownloader(headers: [String: String], subPlaylists: [String: String]) -> VideoHLSDownloader {
        VideoHLSDownloader(client: client, headers: headers, subPlaylists: subPlaylists, quality: quality, progress: progress)
    }

    // MARK: - Phụ đề

    /// Phụ đề đầu tiên (đúng cái trình phát dùng). Lỗi phụ đề không làm hỏng tập.
    private func downloadSubtitle(_ track: VideoTrack, directory: URL) async -> (entries: [VideoEpisodeManifest.Subtitle], bytes: Int64) {
        guard let subtitle = track.subtitles.first else { return ([], 0) }
        do {
            let text = try await subtitleText(subtitle, headers: track.headers)
            guard !VideoSubtitleParser.parse(text).isEmpty else {
                AppLogger.shared.log("❌ [VideoOffline] Phụ đề không có dòng nào đọc được — bỏ qua")
                return ([], 0)
            }
            let isVTT = VideoDataURI.stripBOM(text).trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("WEBVTT")
            let fileName = "sub1." + (isVTT ? "vtt" : "srt")
            let data = Data(text.utf8)
            try VideoOfflineStore.writeAtomic(data, to: directory.appendingPathComponent(fileName, isDirectory: false))
            return ([VideoEpisodeManifest.Subtitle(file: fileName, label: subtitle.label, language: subtitle.language)], Int64(data.count))
        } catch {
            if !(error is CancellationError) {
                AppLogger.shared.log("❌ [VideoOffline] Không tải được phụ đề: \(error.localizedDescription)")
            }
            return ([], 0)
        }
    }

    private func subtitleText(_ subtitle: VideoSubtitleTrack, headers: [String: String]) async throws -> String {
        let probe = subtitle.data.trimmingCharacters(in: .whitespacesAndNewlines)
        if VideoDataURI.isDataURI(probe) {
            return VideoDataURI.decode(probe)?.text ?? ""
        }
        let candidate = probe.hasPrefix("//") ? "https:" + probe : probe
        if !candidate.contains("\n"), let url = URL(string: candidate), url.host != nil,
           let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
            let data = try await client.data(from: url, headers: headers)
            return String(data: data, encoding: .utf8) ?? TextEncodingDecoder.decode(data)
        }
        return subtitle.data
    }

    // MARK: - Tiện ích

    private func orderedServers(_ servers: [VideoServer]) -> [VideoServer] {
        guard let remembered = rememberedServerTitle,
              let index = servers.firstIndex(where: { $0.title == remembered }), index > 0 else { return servers }
        var ordered = servers
        ordered.insert(ordered.remove(at: index), at: 0)
        return ordered
    }

    /// `VideoSourceResolver` là `@MainActor` (webview dò link) — dựng và gọi trên main.
    @MainActor
    private static func resolve(_ track: VideoTrack, packageId: String, localPath: String) async throws -> VideoSourceResolution {
        let resolver = VideoSourceResolver(extensionPackageId: packageId)
        return try await resolver.resolveSource(track, extensionLocalPath: localPath)
    }

    /// Đuôi/MIME rõ ràng thì tin luôn; còn lại hỏi `VideoHLSPlaylistProbe` (tải thử playlist). Không mở được ⇒ lỗi
    /// (không đoán là file mp4).
    private static func isHLS(url: URL, mimeType: String?, headers: [String: String]) async throws -> Bool {
        let ext = url.pathExtension.lowercased()
        let mime = mimeType?.lowercased() ?? ""
        if ext == "m3u8" || ext == "m3u" || mime.contains("mpegurl") { return true }
        if ["mp4", "m4v", "mov"].contains(ext) || mime.hasPrefix("video/mp4") || mime.hasPrefix("video/quicktime") {
            return false
        }
        switch await VideoHLSPlaylistProbe.shape(ofRemote: url, headers: headers) {
        case .master, .media: return true
        case .notPlaylist: return false
        case .unavailable: throw PipelineError.unreachable
        }
    }
}
