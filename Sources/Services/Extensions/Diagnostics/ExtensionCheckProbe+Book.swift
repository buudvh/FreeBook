import Foundation

/// Truyện thử của Kiểm tra tiện ích: `detail`, `page` → `toc` → `chap` (chữ / danh sách ảnh + ảnh đầu / server) →
/// `track`, và `voice` của tiện ích TTS. `host` đi như app: host của mục → `detail` / `page` / `toc`; host của chương
/// (thiếu thì của mục) → `chap`.
extension ExtensionCheckProbe {
    struct ChapterRef: Sendable {
        let url: String
        let host: String?
    }

    struct TocOutput: Sendable {
        let total: Int
        let chapter: ChapterRef?
    }

    struct ComicOutput: Sendable {
        let pages: Int
        let firstBytes: Int
    }

    struct ServerOutput: Sendable {
        let count: Int
        let firstData: String?
    }

    struct TrackOutput: Sendable {
        let kind: String
        let probedBytes: Int?
    }

    static let bookKeys = ["detail", "page", "toc", "chap", "track"]

    func runBookChain() async throws {
        guard let book = books["search"] ?? books["home"] ?? books["explore"] ?? books["genre"] else {
            skipPending(Self.bookKeys, reason: "Bỏ qua — không lối vào nào cho ra truyện để thử")
            await publish()
            return
        }
        result.bookName = book.name
        result.bookSource = book.source
        await publish()

        // `toc` dùng link của mục, không cần kết quả `detail` ⇒ `detail` lỗi vẫn chạy tiếp để kiểm đủ script.
        try await runDetail(book)
        guard let tocURL = try await runPage(book) else {
            skipPending(["toc", "chap", "track"], reason: "Bỏ qua — vì page lỗi")
            await publish()
            return
        }
        guard let chapter = try await runToc(url: tocURL, book: book) else {
            skipPending(["chap", "track"], reason: "Bỏ qua — vì không lấy được mục lục")
            await publish()
            return
        }
        switch kind {
        case .comic: try await runComic(chapter, book: book)
        case .video: try await runVideo(chapter, book: book)
        default: try await runText(chapter, book: book)
        }
    }

    // MARK: - detail / page / toc

    private func runDetail(_ book: BookRef) async throws {
        guard isRunnable("detail") else { return }
        let path = target.localPath
        let downloadUrl = target.downloadUrl
        let config = target.configJson
        _ = try await perform("detail", seconds: Self.detailSeconds, fallbackURL: book.link, host: book.host, operation: { () async throws -> String in
            let detail = try await SourceRuntime.shared.detail(
                localPath: path, downloadUrl: downloadUrl, url: book.link, host: book.host, configJson: config
            )
            return detail.name.trimmingCharacters(in: .whitespacesAndNewlines)
        }, check: { name in
            name.isEmpty ? .empty("Chi tiết không có tên truyện") : .pass("«\(name)»")
        })
    }

    /// URL để chạy `toc`: không khai `page` ⇒ link của mục; `page` ra trang ⇒ trang đầu; `page` trả rỗng ⇒ link của mục
    /// (như `BookDetailLoader.fetchFirstPageTOC`, dòng `page` vẫn ghi lỗi); `page` lỗi ⇒ `nil`.
    private func runPage(_ book: BookRef) async throws -> String? {
        guard row("page") != nil else { return book.link }
        guard isRunnable("page") else { return nil }
        let path = target.localPath
        let downloadUrl = target.downloadUrl
        let config = target.configJson
        let pages = try await perform("page", seconds: Self.detailSeconds, fallbackURL: book.link, host: book.host, operation: { () async throws -> [String] in
            try await SourceRuntime.shared.page(
                localPath: path, downloadUrl: downloadUrl, url: book.link, host: book.host, configJson: config
            )
        }, check: { pages in
            pages.isEmpty ? .empty("page trả 0 trang mục lục") : .pass("\(pages.count) trang mục lục")
        })
        if let first = pages?.first { return first }
        return row("page")?.failureClass == .noMatch ? book.link : nil
    }

    private func runToc(url: String, book: BookRef) async throws -> ChapterRef? {
        guard isRunnable("toc") else { return nil }
        let path = target.localPath
        let downloadUrl = target.downloadUrl
        let config = target.configJson
        let unit = kind == .video ? "tập" : "chương"
        let output = try await perform("toc", seconds: Self.tocSeconds, fallbackURL: url, host: book.host, operation: { () async throws -> TocOutput in
            let chapters = try await SourceRuntime.shared.toc(
                localPath: path, downloadUrl: downloadUrl, url: url, host: book.host, configJson: config
            )
            let first = chapters.first { !$0.isSection && ExtensionCheckProbe.nonEmpty($0.url) != nil }
            let chapter = first.map { ChapterRef(url: $0.url, host: ExtensionCheckProbe.nonEmpty($0.host)) }
            return TocOutput(total: chapters.count, chapter: chapter)
        }, check: { output in
            if output.chapter != nil { return .pass("\(output.total) \(unit)") }
            return .empty(output.total == 0 ? "Mục lục trả 0 \(unit)" : "Mục lục có \(output.total) dòng nhưng không \(unit) nào có URL")
        })
        return output?.chapter
    }

    // MARK: - chap

    private func runText(_ chapter: ChapterRef, book: BookRef) async throws {
        guard isRunnable("chap") else { return }
        let path = target.localPath
        let downloadUrl = target.downloadUrl
        let config = target.configJson
        let host = chapter.host ?? book.host
        _ = try await perform("chap", seconds: Self.contentSeconds, fallbackURL: chapter.url, host: host, operation: { () async throws -> Int in
            let text = try await SourceRuntime.shared.chap(
                localPath: path, downloadUrl: downloadUrl, url: chapter.url, host: host, configJson: config
            )
            return text.trimmingCharacters(in: .whitespacesAndNewlines).count
        }, check: { length in
            length > 0 ? .pass("\(length.formatted()) ký tự") : .empty("Nội dung chương rỗng")
        })
    }

    /// Danh sách ảnh rồi tải ảnh đầu qua `ComicImageLoader` (chạy script ảnh nếu mục ảnh có `script`) — đúng đường màn
    /// đọc truyện tranh.
    private func runComic(_ chapter: ChapterRef, book: BookRef) async throws {
        guard isRunnable("chap") else { return }
        let path = target.localPath
        let downloadUrl = target.downloadUrl
        let config = target.configJson
        let host = chapter.host ?? book.host
        _ = try await perform("chap", seconds: Self.mediaSeconds, fallbackURL: chapter.url, host: host, operation: { () async throws -> ComicOutput in
            let pages = try await SourceRuntime.shared.comicPages(
                localPath: path, downloadUrl: downloadUrl, url: chapter.url, host: host, configJson: config
            )
            guard let first = pages.first else { return ComicOutput(pages: 0, firstBytes: 0) }
            let request = ComicImageRequest(source: first, chapterUrl: chapter.url, extensionLocalPath: path,
                                            downloadUrl: downloadUrl, configJson: config)
            let data: Data
            do {
                data = try await ComicImageLoader.shared.data(for: request)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                let classified = LegadoCorpusErrorClassifier.classify(ExtensionLoadError.unwrapped(error))
                throw LegadoCorpusErrorClassifier.StepFailure(failureClass: classified.failureClass,
                                                              message: "Ảnh đầu: \(classified.message)")
            }
            return ComicOutput(pages: pages.count, firstBytes: data.count)
        }, check: { output in
            guard output.pages > 0 else { return .empty("Chương không có ảnh nào") }
            guard output.firstBytes > 0 else { return .empty("Ảnh đầu rỗng") }
            let size = ByteCountFormatter.string(fromByteCount: Int64(output.firstBytes), countStyle: .file)
            return .pass("\(output.pages) ảnh · ảnh đầu \(size)")
        })
    }

    /// Danh sách server (`chap`) rồi nguồn phát của server đầu (`track`); nguồn `native` http(s) ⇒ tải 1 KB đầu
    /// (`LegadoCorpusProbe.probeMedia`: mã 2xx, playlist `.m3u8` phải bắt đầu `#EXTM3U`).
    private func runVideo(_ chapter: ChapterRef, book: BookRef) async throws {
        guard isRunnable("chap") else { return }
        let path = target.localPath
        let downloadUrl = target.downloadUrl
        let config = target.configJson
        let host = chapter.host ?? book.host
        let servers = try await perform("chap", seconds: Self.contentSeconds, fallbackURL: chapter.url, host: host, operation: { () async throws -> ServerOutput in
            let servers = try await SourceRuntime.shared.videoServers(
                localPath: path, downloadUrl: downloadUrl, url: chapter.url, host: host, configJson: config
            )
            return ServerOutput(count: servers.count, firstData: servers.first?.data)
        }, check: { output in
            output.count > 0 ? .pass("\(output.count) server") : .empty("Tập không có server phát nào")
        })
        guard let data = servers?.firstData else {
            skipPending(["track"], reason: "Bỏ qua — vì chap không ra server")
            await publish()
            return
        }
        guard isRunnable("track") else { return }
        _ = try await perform("track", seconds: Self.mediaSeconds, fallbackURL: chapter.url, host: host, operation: { () async throws -> TrackOutput in
            let track = try await SourceRuntime.shared.videoTrack(
                localPath: path, downloadUrl: downloadUrl, data: data, configJson: config
            )
            let link = track.data.trimmingCharacters(in: .whitespacesAndNewlines)
            guard track.kind == .native, let url = URL(string: link), let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https" else {
                return TrackOutput(kind: track.kind.rawValue, probedBytes: nil)
            }
            let bytes = try await LegadoCorpusProbe.probeMedia(url: url, headers: track.headers)
            return TrackOutput(kind: track.kind.rawValue, probedBytes: bytes)
        }, check: { output in
            guard let bytes = output.probedBytes else { return .pass("Nguồn phát \(output.kind)") }
            return .pass("Nguồn phát \(output.kind) · tải thử \(bytes) byte đầu")
        })
    }

    // MARK: - TTS

    func runVoice() async throws {
        guard isRunnable("voice") else { return }
        let path = target.localPath
        let downloadUrl = target.downloadUrl
        let config = target.configJson
        _ = try await perform("voice", seconds: Self.listSeconds, fallbackURL: sourceURL, operation: { () async throws -> Int in
            try await ExtensionManager.shared.ttsVoices(localPath: path, downloadUrl: downloadUrl, configJson: config).count
        }, check: { count in
            count > 0 ? .pass("\(count) giọng") : .empty("Không có giọng nào")
        })
    }
}
