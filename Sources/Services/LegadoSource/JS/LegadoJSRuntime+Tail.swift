import Foundation

/// Phía Swift của phần đuôi đợt 2 (spec §13.3, §13.7–§13.9, §14.8): `java.refreshTocUrl`/`reGetBook`,
/// `java.importScript`, `java.cacheFile`, `java.toURL`, `Jsoup.connect`, `java.webViewGetSource`/`OverrideUrl`.
extension LegadoJSRuntime {
    func nativeTail(_ command: String, _ arguments: LegadoJSArguments, _ session: LegadoEngineSession) throws -> String? {
        switch command {
        case "refreshTocUrl":
            try session.jsRefreshTocUrl()
            return ""
        case "reGetBook":
            try session.jsReGetBook()
            return ""
        case "importScript":
            return try session.jsImportScript(text(of: arguments[0]))
        case "cacheFile":
            return try session.jsCacheFile(text(of: arguments[0]), saveTime: arguments.number(1))
        case "toURL":
            let base = arguments.plainString(1) ?? session.currentFrameBaseUrl ?? session.sourceBase
            return Self.urlParts(LegadoURLResolver.absolute(text(of: arguments[0]), base: base)).compactText
        case "jsoupConnect":
            guard let spec = jsonObject(arguments[0]) else { throw LegadoJSNativeError("Jsoup.connect: tham số hỏng") }
            let outcome = try session.jsoupRequest(spec)
            var json = Self.responseJSON(outcome.response)
            if case .object(var entries) = json {
                if outcome.response == nil, let error = outcome.error {
                    entries.append((key: "message", value: .string(error)))
                }
                if let response = outcome.response, spec["wantBytes"].map({ LegadoBookContext.truthy($0) }) == true {
                    entries.append((key: "hex", value: .string(Self.hex(response.data))))
                }
                json = .object(entries)
            }
            return json.compactText
        case "webViewGetSource", "webViewGetOverrideUrl":
            let pattern = arguments.plainString(3)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !pattern.isEmpty else { return "" }
            return try session.jsWebViewResource(html: arguments.plainString(0), url: arguments.plainString(1),
                                                 pattern: pattern)
        default:
            return nil
        }
    }

    /// `java.toURL` (spec §13.8): các thành phần kiểu `URL` của trình duyệt.
    static func urlParts(_ href: String) -> LegadoEngineJSON {
        let components = URLComponents(string: href) ?? URLComponents(string: LegadoURLEncoder.encodeURL(href, encoding: .utf8))
        let scheme = components?.scheme ?? ""
        let hostname = components?.host ?? ""
        let port = components?.port.map { String($0) } ?? ""
        let host = port.isEmpty ? hostname : hostname + ":" + port
        let path = components?.percentEncodedPath ?? ""
        let search = components?.percentEncodedQuery.map { "?" + $0 } ?? ""
        let hash = components?.percentEncodedFragment.map { "#" + $0 } ?? ""
        let fields: [(String, String)] = [
            ("href", href), ("protocol", scheme.isEmpty ? "" : scheme + ":"), ("host", host), ("hostname", hostname),
            ("port", port), ("pathname", path.isEmpty ? "/" : path), ("search", search), ("hash", hash),
            ("origin", scheme.isEmpty ? "" : scheme + "://" + host)
        ]
        return .object(fields.map { (key: $0.0, value: LegadoEngineJSON.string($0.1)) })
    }
}
