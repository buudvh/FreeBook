import Foundation

/// Truyện tranh (spec §8): nội dung chương → danh sách ảnh `ComicPageSource`. Chuỗi `content` **không** đi pipeline chữ
/// (không `ChapterTextNormalizer`, dịch, TTS, không cache ở `ChapterContentRepository`).
extension LegadoSourceRuntime {
    /// Chương nhiều ảnh hơn mức này chỉ ghi chẩn đoán (spec §8.8), không cắt.
    static let comicImageWarningCount = 500

    /// Ảnh của chương ở `chapterUrl`: tải + phân trang `nextContentUrl` (URL dừng = chương kế, §8.8) + `replaceRegex` trên
    /// HTML (§8.2 bước 1) → tách `<img>` (§8.2.1) → mỗi ảnh một `ComicPageSource` với header đã gộp (§8.3).
    /// Nguồn có `imageDecode` ⇒ `script` = `SourceRuntime.legadoImageDecodeScriptName`, `link` = chuỗi `src` đầy đủ (URL
    /// tuyệt đối + khối option) để bước giải mã tải lại đúng request đó (§8.6).
    static func comicPages(_ target: Target, chapterUrl: String, context: SourceRuntimeContext?, log: LegadoRunLog? = nil) async throws -> [ComicPageSource] {
        let decodes = nonEmpty(target.source.ruleContent.imageDecode) != nil
        let pages: [ComicPageSource] = try await runChapterSession(target, chapterUrl: chapterUrl, context: context, log: log) { session, nextURL in
            let collected = try Self.collectContent(session: session, target: target, chapterUrl: chapterUrl, stopURL: nextURL)
            guard !Self.trimmed(collected.html).isEmpty else {
                throw Self.emptyResultError(session, "nội dung chương (content)")
            }
            let images = LegadoComicImageExtractor.images(in: collected.html)
            guard !images.isEmpty else {
                // Nguồn "tranh" thực chất trả chữ/link (spec §8.2 bước 6): đưa đoạn chữ đã làm sạch vào thông báo lỗi.
                let text = LegadoHTMLText.plainText(fromHTML: collected.html)
                throw LegadoRuntimeError.comicWithoutImages(String(text.prefix(600)))
            }
            if images.count > Self.comicImageWarningCount {
                session.diagnostics.record(.info, "Chương có \(images.count) ảnh")
            }
            return try Self.pageSources(session: session, images: images, pageURL: collected.pageURL, decodes: decodes)
        }
        guard !pages.isEmpty else { throw LegadoRuntimeError.comicWithoutImages("") }
        return pages
    }

    /// Ảnh → `ComicPageSource`. URL ghép tuyệt đối theo URL cuối của trang chương; `//host` thêm scheme; `data:` giữ
    /// nguyên. Header = header mặc định < nguồn (gồm đăng nhập) < option của ảnh — dựng bằng chính `buildRequest` của
    /// engine — cộng cookie trong kho cho tên miền ảnh; thiếu `Referer` ⇒ `Referer` = URL trang chương (khuyến nghị U29).
    static func pageSources(
        session: LegadoEngineSession,
        images: [LegadoComicImageExtractor.RawImage],
        pageURL: String,
        decodes: Bool
    ) throws -> [ComicPageSource] {
        var output: [ComicPageSource] = []
        output.reserveCapacity(images.count)
        for image in images {
            try session.checkCancellation()
            let absolute = LegadoURLResolver.absolute(image.url, base: pageURL)
            if absolute.lowercased().hasPrefix("data:") {
                output.append(ComicPageSource(link: absolute))
                continue
            }
            guard LegadoURLResolver.hasHTTPScheme(absolute) else {
                session.diagnostics.record(.info, "Bỏ ảnh không phải http(s): \(absolute.prefix(80))")
                continue
            }
            let rule = image.option.map { absolute + "," + $0 } ?? absolute
            let request: LegadoHTTPRequest
            do {
                request = try session.buildRequest(rule, baseUrl: pageURL)
            } catch let error as LegadoEngineError {
                session.diagnostics.record(.ruleSyntax, "Không dựng được request ảnh: \(error.localizedDescription)")
                continue
            }
            var headers = headerDictionary(request.headers)
            let manualCookie = request.header("Cookie")
            if let cookie = LegadoHTTPRequest.mergeCookies(jar: session.cookieJar.cookieHeader(forURL: request.url),
                                                           manual: manualCookie), !cookie.isEmpty {
                setHeader("Cookie", cookie, in: &headers)
            }
            let hasReferer = request.header("Referer").map { !$0.isEmpty } ?? false
            if !hasReferer { setHeader("Referer", pageURL, in: &headers) }
            let referer = request.header("Referer") ?? pageURL
            if decodes {
                // Bước giải mã chỉ nhận `link`: Referer tự thêm phải nằm trong khối option để request tải lại giống hệt.
                let link = hasReferer ? rule : addingReferer(pageURL, to: rule)
                output.append(ComicPageSource(link: link, script: SourceRuntime.legadoImageDecodeScriptName,
                                              referer: referer, headers: headers))
            } else {
                output.append(ComicPageSource(link: request.url, referer: referer, headers: headers))
            }
        }
        return output
    }

    /// Cặp header (đã gộp không phân biệt hoa thường) → từ điển cho `ComicPageSource`/`VideoTrack`.
    static func headerDictionary(_ pairs: [(name: String, value: String)]) -> [String: String] {
        var output: [String: String] = [:]
        for pair in pairs {
            setHeader(pair.name, pair.value, in: &output)
        }
        return output
    }

    static func setHeader(_ name: String, _ value: String, in headers: inout [String: String]) {
        for key in headers.keys where key.caseInsensitiveCompare(name) == .orderedSame {
            headers.removeValue(forKey: key)
        }
        headers[name] = value
    }

    /// Thêm `Referer` vào khối option của rule URL ảnh (tạo khối nếu chưa có). Khối không đọc được hoặc `headers` không
    /// phải object ⇒ giữ nguyên rule (không đoán).
    static func addingReferer(_ referer: String, to rule: String) -> String {
        let parts = LegadoURLResolver.splitOption(rule)
        let refererEntry: (key: String, value: LegadoEngineJSON) = (key: "Referer", value: .string(referer))
        guard let optionText = parts.option else {
            let option = LegadoEngineJSON.object([(key: "headers", value: .object([refererEntry]))])
            return parts.url + "," + option.compactText
        }
        guard let json = LegadoEngineJSONParser.parse(optionText, lenient: true), var entries = json.objectEntries else {
            return rule
        }
        if let index = entries.firstIndex(where: { $0.key.lowercased() == "headers" }) {
            guard case .object(var headerEntries) = entries[index].value else { return rule }
            headerEntries.append(refererEntry)
            entries[index] = (key: entries[index].key, value: .object(headerEntries))
        } else {
            entries.append((key: "headers", value: .object([refererEntry])))
        }
        return parts.url + "," + LegadoEngineJSON.object(entries).compactText
    }
}
