import Foundation

/// Dựng `LegadoRequestSpec` từ một rule URL của Legado.
///
/// Thứ tự xử lý bám theo `AnalyzeUrl.initUrl` (`:150-158`): chạy `@js:`/`<js>` → thay `{{key}}`,
/// `{{page}}` và `<a,b,c>` → tách khối tuỳ chọn → resolve URL tuyệt đối → encode query/body.
public enum LegadoUrlBuilder {

    /// `evaluateJS` nhận (mã JS, url hiện tại) và trả về url mới; `nil` nghĩa là không đổi.
    public static func build(
        rule: String,
        baseUrl: String,
        key: String? = nil,
        page: Int? = nil,
        sourceHeaders: [String: String] = [:],
        interpolate: (String) -> String,
        evaluateJS: ((String, String) -> String?)? = nil
    ) -> LegadoRequestSpec {
        var working = rule.trimmingCharacters(in: .whitespacesAndNewlines)

        // 1. `@js:` / `<js>` — `@result` là url tính tới thời điểm đó.
        working = applyScriptBlocks(working, evaluateJS: evaluateJS)

        // 2. `{{…}}` (gồm `{{key}}`, `{{page}}`) do caller nội suy vì cần túi biến và JS runtime.
        working = interpolate(working)

        // 3. Cú pháp cũ: `searchKey` / `searchPage` viết trần.
        if let key {
            working = working.replacingOccurrences(of: "searchKey", with: key)
        }
        if let page {
            working = working.replacingOccurrences(of: "searchPage", with: String(page))
        }

        // 4. `<a,b,c>` — chọn theo số trang (`AnalyzeUrl.kt:206-216`).
        if let page {
            working = applyPageAlternatives(working, page: page)
        }

        // 5. Tách khối tuỳ chọn.
        let (rawUrl, option) = LegadoUrlOption.split(working)
        var absolute = resolve(rawUrl.trimmingCharacters(in: .whitespacesAndNewlines), baseUrl: baseUrl)

        var headers = sourceHeaders
        for (name, value) in option?.headers ?? [:] {
            headers[name] = value
        }
        headers.removeValue(forKey: "proxy")

        let charset = option?.charset
        let method = option?.method ?? "GET"
        var body: Data?

        if method == "POST" {
            body = encodeBody(option, charset: charset, headers: &headers)
        } else if let questionIndex = absolute.firstIndex(of: "?") {
            // Query của GET cũng phải encode theo charset của nguồn.
            let head = String(absolute[absolute.startIndex..<questionIndex])
            let query = String(absolute[absolute.index(after: questionIndex)...])
            absolute = head + "?" + LegadoPercentEncoder.encodeQueryString(query, charset: charset)
        }

        return LegadoRequestSpec(
            url: absolute,
            method: method,
            headers: headers,
            body: body,
            charset: charset,
            retry: option?.retry ?? 0,
            requiresWebView: option?.webView ?? false
        )
    }

    // MARK: - Từng bước

    /// Chạy `@js:` / `<js></js>` trong chuỗi URL — port `AnalyzeUrl.analyzeJs` (`:162-185`).
    ///
    /// Ngữ nghĩa dễ hiểu sai: phần **văn bản thường** không được nối vào kết quả mà **thay thế** kết
    /// quả, với `@result` là chỗ chèn kết quả trước đó. Còn khối JS nhận kết quả trước đó qua biến
    /// `result`.
    private static func applyScriptBlocks(
        _ raw: String,
        evaluateJS: ((String, String) -> String?)?
    ) -> String {
        guard let evaluateJS else { return raw }
        let blocks = scriptBlocks(in: raw)
        guard !blocks.isEmpty else { return raw }

        var result = raw
        var cursor = raw.startIndex

        for block in blocks {
            if block.range.lowerBound > cursor {
                let plain = String(raw[cursor..<block.range.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !plain.isEmpty {
                    result = plain.replacingOccurrences(of: "@result", with: result)
                }
            }
            result = evaluateJS(block.code, result) ?? result
            cursor = block.range.upperBound
        }

        if cursor < raw.endIndex {
            let plain = String(raw[cursor...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !plain.isEmpty {
                result = plain.replacingOccurrences(of: "@result", with: result)
            }
        }
        return result
    }

    private struct ScriptBlock {
        let range: Range<String.Index>
        let code: String
    }

    private static func scriptBlocks(in raw: String) -> [ScriptBlock] {
        var blocks: [ScriptBlock] = []
        var searchStart = raw.startIndex

        while searchStart < raw.endIndex {
            let tail = raw[searchStart...]
            let openTag = tail.range(of: "<js>", options: .caseInsensitive)
            let atJs = tail.range(of: "@js:", options: .caseInsensitive)

            if let openTag, atJs == nil || openTag.lowerBound < atJs!.lowerBound {
                guard let closeTag = raw[openTag.upperBound...]
                    .range(of: "</js>", options: .caseInsensitive) else {
                    blocks.append(ScriptBlock(
                        range: openTag.lowerBound..<raw.endIndex,
                        code: String(raw[openTag.upperBound...])
                    ))
                    break
                }
                blocks.append(ScriptBlock(
                    range: openTag.lowerBound..<closeTag.upperBound,
                    code: String(raw[openTag.upperBound..<closeTag.lowerBound])
                ))
                searchStart = closeTag.upperBound
                continue
            }

            if let atJs {
                // `@js:` ăn tới hết chuỗi.
                blocks.append(ScriptBlock(
                    range: atJs.lowerBound..<raw.endIndex,
                    code: String(raw[atJs.upperBound...])
                ))
            }
            break
        }
        return blocks
    }

    /// `<url1,url2,url3>` — trang 1 lấy phần tử 1, vượt số phần tử thì lấy phần tử cuối.
    private static func applyPageAlternatives(_ raw: String, page: Int) -> String {
        guard let regex = try? NSRegularExpression(pattern: "<([^<>]*)>", options: []) else {
            return raw
        }
        let text = raw as NSString
        var result = raw
        let matches = regex.matches(in: raw, options: [], range: NSRange(location: 0, length: text.length))
        for match in matches.reversed() {
            guard match.numberOfRanges > 1 else { continue }
            let inner = text.substring(with: match.range(at: 1))
            let options = inner.components(separatedBy: ",")
            guard options.count > 1 else { continue }
            let chosen = page <= options.count && page >= 1
                ? options[page - 1]
                : (options.last ?? inner)
            let whole = text.substring(with: match.range)
            if let range = result.range(of: whole) {
                result.replaceSubrange(range, with: chosen.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        return result
    }

    private static func encodeBody(
        _ option: LegadoUrlOption?,
        charset: String?,
        headers: inout [String: String]
    ) -> Data? {
        guard let option, let rawBody = option.body else { return nil }
        let hasContentType = headers.keys.contains { $0.lowercased() == "content-type" }

        if option.bodyIsJSON {
            if !hasContentType {
                headers["Content-Type"] = "application/json; charset=" + (charset ?? "utf-8")
            }
            return LegadoPercentEncoder.encodeToData(rawBody, charset: charset)
        }

        let trimmed = rawBody.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("<") {
            if !hasContentType { headers["Content-Type"] = "text/xml" }
            return LegadoPercentEncoder.encodeToData(rawBody, charset: charset)
        }

        // Body dạng form: encode từng cặp theo charset của nguồn.
        if !hasContentType {
            headers["Content-Type"] = "application/x-www-form-urlencoded"
        }
        let encoded = LegadoPercentEncoder.encodeQueryString(rawBody, charset: charset)
        return encoded.data(using: .ascii) ?? encoded.data(using: .utf8)
    }

    /// URL tương đối → tuyệt đối. Giữ nguyên khi đã là tuyệt đối hoặc là scheme lạ.
    public static func resolve(_ raw: String, baseUrl: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return baseUrl }
        let lower = trimmed.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") { return trimmed }
        if lower.hasPrefix("//") {
            let scheme = baseUrl.lowercased().hasPrefix("http://") ? "http:" : "https:"
            return scheme + trimmed
        }
        guard let base = URL(string: baseUrl) else { return trimmed }
        return URL(string: trimmed, relativeTo: base)?.absoluteString ?? trimmed
    }

    /// Gốc `scheme://host` của một URL — dùng làm `baseUrl` cho các bước sau.
    public static func origin(of urlString: String) -> String? {
        guard let url = URL(string: urlString),
              let scheme = url.scheme,
              let host = url.host else { return nil }
        if let port = url.port {
            return "\(scheme)://\(host):\(port)"
        }
        return "\(scheme)://\(host)"
    }
}
