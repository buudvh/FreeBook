import Foundation

/// Bước media của bộ nghiệm thu (nguồn tranh/video): thay bước nội dung chữ, ghi vào `Step.content` + `MediaCheck`.
/// Mọi lời gọi qua `SourceRuntime.shared` / `ComicImageLoader` — đúng đường màn đọc tranh và trình phát dùng.
extension LegadoCorpusProbe {
    /// Trần của cả bước media (danh sách + ảnh đầu, hoặc server + nguồn phát + 1 KB đầu).
    static let mediaSeconds = 180

    /// Gom kết quả từng bước con từ closure `@Sendable` của `measure` (có thể bị bỏ chờ khi vượt trần ⇒ cần khoá).
    final class MediaBox: @unchecked Sendable {
        struct Draft {
            var items = 0
            var firstItemBytes: Int?
            var trackKind: String?
            var decoded = false
            var stage: String? = "list"
        }

        private let lock = NSLock()
        private let kind: String
        private var draft = Draft()

        init(kind: String) {
            self.kind = kind
        }

        func update(_ change: (inout Draft) -> Void) {
            lock.lock()
            change(&draft)
            lock.unlock()
        }

        var snapshot: LegadoCorpusReport.MediaCheck {
            lock.lock()
            defer { lock.unlock() }
            return LegadoCorpusReport.MediaCheck(kind: kind, items: draft.items, firstItemBytes: draft.firstItemBytes,
                                                 trackKind: draft.trackKind, decoded: draft.decoded,
                                                 failedStage: draft.stage)
        }
    }

    func mediaContent(_ chapter: ChapterRef, bookURL: String?, book: BookRef?) async throws {
        let path = candidate.localPath
        let downloadUrl = candidate.downloadUrl
        let config = candidate.configJson
        let host = book?.host
        let chapterURL = chapter.url
        let context = makeContext(bookURL: bookURL, book: book, chapter: chapter)
        let isComic = kind == .comic
        let box = MediaBox(kind: isComic ? "comic" : "video")
        defer { mediaCheck = box.snapshot }
        _ = try await measure(.content, seconds: Self.mediaSeconds, operation: { () async throws -> Int in
            if isComic {
                return try await LegadoCorpusProbe.probeComic(path: path, downloadUrl: downloadUrl, config: config,
                                                              chapterURL: chapterURL, host: host, context: context, box: box)
            }
            return try await LegadoCorpusProbe.probeVideo(path: path, downloadUrl: downloadUrl, config: config,
                                                          chapterURL: chapterURL, host: host, context: context, box: box)
        }, evaluate: { (count: $0, ok: $0 > 0) })
    }

    // MARK: - Tranh

    static func probeComic(
        path: String, downloadUrl: String, config: String, chapterURL: String, host: String?,
        context: SourceRuntimeContext, box: MediaBox
    ) async throws -> Int {
        let pages = try await SourceRuntime.shared.comicPages(localPath: path, downloadUrl: downloadUrl, url: chapterURL,
                                                              host: host, configJson: config, context: context)
        box.update { $0.items = pages.count }
        guard let first = pages.first else {
            throw StepFailure(failureClass: .noMatch, message: "Chương tranh không có ảnh nào")
        }
        box.update {
            $0.decoded = first.script == SourceRuntime.legadoImageDecodeScriptName
            $0.stage = "item"
        }
        let request = ComicImageRequest(source: first, chapterUrl: chapterURL, extensionLocalPath: path,
                                        downloadUrl: downloadUrl, configJson: config)
        let data: Data
        do {
            data = try await ComicImageLoader.shared.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            let classified = LegadoCorpusErrorClassifier.classify(error)
            throw StepFailure(failureClass: classified.failureClass, message: "Ảnh đầu: \(classified.message)")
        }
        box.update {
            $0.firstItemBytes = data.count
            $0.stage = nil
        }
        return pages.count
    }

    // MARK: - Video

    static func probeVideo(
        path: String, downloadUrl: String, config: String, chapterURL: String, host: String?,
        context: SourceRuntimeContext, box: MediaBox
    ) async throws -> Int {
        let servers = try await SourceRuntime.shared.videoServers(localPath: path, downloadUrl: downloadUrl, url: chapterURL,
                                                                  host: host, configJson: config, context: context)
        box.update { $0.items = servers.count }
        guard let first = servers.first else {
            throw StepFailure(failureClass: .noMatch, message: "Tập không có server phát nào")
        }
        box.update { $0.stage = "track" }
        let track = try await SourceRuntime.shared.videoTrack(localPath: path, downloadUrl: downloadUrl, data: first.data,
                                                              configJson: config)
        box.update { $0.trackKind = track.kind.rawValue }
        let link = track.data.trimmingCharacters(in: .whitespacesAndNewlines)
        if track.kind == .native, let url = URL(string: link), let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            box.update { $0.stage = "probe" }
            let bytes = try await probeMedia(url: url, headers: track.headers)
            box.update { $0.firstItemBytes = bytes }
        }
        box.update { $0.stage = nil }
        return servers.count
    }

    /// Tải 1 KB đầu của nguồn phát (spec §9.7): mã 2xx và có byte; playlist `.m3u8` phải bắt đầu bằng `#EXTM3U`.
    static func probeMedia(url: URL, headers: [String: String]) async throws -> Int {
        var request = URLRequest(url: url, timeoutInterval: 20)
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.setValue("bytes=0-1023", forHTTPHeaderField: "Range")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw StepFailure(failureClass: .http, message: "Nguồn phát trả HTTP \(http.statusCode)")
        }
        guard !data.isEmpty else {
            throw StepFailure(failureClass: .noMatch, message: "Nguồn phát rỗng")
        }
        if url.path.lowercased().hasSuffix(".m3u8") {
            let head = String(decoding: data.prefix(64), as: UTF8.self)
                .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{FEFF}")))
            guard head.hasPrefix("#EXTM3U") else {
                throw StepFailure(failureClass: .noMatch, message: "Playlist không bắt đầu bằng #EXTM3U")
            }
        }
        return data.count
    }
}
