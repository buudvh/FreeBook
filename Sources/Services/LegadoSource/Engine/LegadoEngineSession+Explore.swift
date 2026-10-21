import Foundation

/// Phân tích `exploreUrl` (spec §5.2.1–§5.2.2): mảng JSON, văn bản `tên::url`, hoặc JS sinh một trong hai.
extension LegadoEngineSession {
    /// Danh sách mục khám phá. JS chạy với `baseUrl` = URL gốc nguồn, không có `key`/`page`; placeholder trong URL do
    /// JS sinh **không** được thay ở đây. Mục `type` = `select`/`button` bị ẩn (đợt 2).
    func exploreItems(_ exploreUrl: String) throws -> [LegadoEngineExploreItem] {
        let trimmed = exploreUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let lower = trimmed.lowercased()
        if lower.hasPrefix("@js:") || lower.hasPrefix("<js>") {
            var code = String(trimmed.dropFirst(4))
            if lower.hasPrefix("<js>"), let close = code.range(of: "</js>", options: .caseInsensitive) {
                code = String(code[..<close.lowerBound])
            }
            let savedKey = key
            let savedPage = page
            key = nil
            page = nil
            defer {
                key = savedKey
                page = savedPage
            }
            let value = try evaluateScript(code, result: nil, baseUrl: sourceBase, src: nil)
            return entries(fromScriptResult: value)
        }
        if trimmed.hasPrefix("[") {
            if let array = LegadoEngineJSONParser.parse(trimmed, lenient: true)?.arrayValue {
                return Self.entries(fromJSONItems: array)
            }
            diagnostics.record(.ruleSyntax, "exploreUrl dạng mảng JSON không đọc được")
        }
        return Self.entries(fromText: trimmed)
    }

    private func entries(fromScriptResult value: LegadoContentNode) -> [LegadoEngineExploreItem] {
        switch value {
        case .list(let items):
            var output: [LegadoEngineExploreItem] = []
            for item in items {
                switch item {
                case .json(let json): output.append(contentsOf: Self.entries(fromJSONItems: [json]))
                case .string(let text): output.append(contentsOf: Self.entries(fromText: text))
                default: continue
                }
            }
            return output
        case .json(let json):
            if let array = json.arrayValue { return Self.entries(fromJSONItems: array) }
            return Self.entries(fromJSONItems: [json])
        case .string(let text):
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("["), let array = LegadoEngineJSONParser.parse(trimmed, lenient: true)?.arrayValue {
                return Self.entries(fromJSONItems: array)
            }
            return Self.entries(fromText: trimmed)
        default:
            return []
        }
    }

    private static let requestOptionKeys: Set<String> = ["webview", "method", "body", "headers", "charset", "js", "webviewdelaytime", "retry"]

    static func entries(fromJSONItems items: [LegadoEngineJSON]) -> [LegadoEngineExploreItem] {
        var output: [LegadoEngineExploreItem] = []
        for item in items {
            guard let fields = item.objectEntries else {
                if case .string(let text) = item { output.append(contentsOf: Self.entries(fromText: text)) }
                continue
            }
            let type = item["type"]?.scalarString.lowercased() ?? ""
            if type == "select" || type == "button" { continue }
            let title = (item["title"]?.scalarString ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            var url = item["url"].map { $0.isNull ? "" : $0.scalarString }?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let extras = fields.filter { requestOptionKeys.contains($0.key.lowercased()) }
            if !url.isEmpty, !extras.isEmpty, LegadoURLResolver.splitOption(url).option == nil {
                url += "," + LegadoEngineJSON.object(extras).compactText
            }
            let style = item["style"]
            output.append(LegadoEngineExploreItem(
                title: title,
                url: url.isEmpty || url == "null" ? nil : url,
                flexBasisPercent: style?["layout_flexBasisPercent"]?.doubleValue,
                flexGrow: style?["layout_flexGrow"]?.doubleValue,
                wrapBefore: (style?["layout_wrapBefore"]).map { LegadoRuleValue.isTruthy($0.scalarString) } ?? false
            ))
        }
        return output
    }

    /// Dạng văn bản: mỗi mục `tên::url`, phân cách bằng xuống dòng hoặc `&&`; tách tại `::` đầu tiên.
    /// Dòng không có `::` là tiêu đề nhóm (bỏ dòng `null`).
    static func entries(fromText text: String) -> [LegadoEngineExploreItem] {
        var pieces: [String] = []
        for line in text.components(separatedBy: "\n") {
            if line.contains("&&"), line.components(separatedBy: "::").count > 2 {
                pieces.append(contentsOf: line.components(separatedBy: "&&"))
            } else {
                pieces.append(line)
            }
        }
        if pieces.count == 1, let only = pieces.first, only.contains("&&") {
            pieces = only.components(separatedBy: "&&")
        }
        var output: [LegadoEngineExploreItem] = []
        for piece in pieces {
            let trimmed = piece.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if let separator = trimmed.range(of: "::") {
                let title = String(trimmed[..<separator.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                let url = String(trimmed[separator.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                output.append(LegadoEngineExploreItem(title: title, url: url.isEmpty ? nil : url))
            } else if trimmed.lowercased() != "null" {
                output.append(LegadoEngineExploreItem(title: trimmed, url: nil))
            }
        }
        return output
    }
}
