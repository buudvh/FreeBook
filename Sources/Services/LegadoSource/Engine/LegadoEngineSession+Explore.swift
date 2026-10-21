import Foundation

/// Phân tích `exploreUrl` (spec §5.2.1–§5.2.2): mảng JSON, văn bản `tên::url`, hoặc JS sinh một trong hai.
extension LegadoEngineSession {
    /// Danh sách mục khám phá **thường** (ô bấm + tiêu đề nhóm) — giữ đúng hành vi đợt 1 cho luồng `genre`: điều khiển
    /// (`select`/`toggle`/`text`/`button`) bị loại. Danh sách đầy đủ có kiểu: `exploreEntries(_:)`.
    /// JS chạy với `baseUrl` = URL gốc nguồn, không có `key`/`page`; placeholder trong URL do JS sinh **không** được thay ở đây.
    func exploreItems(_ exploreUrl: String) throws -> [LegadoEngineExploreItem] {
        try exploreEntriesIncludingControls(exploreUrl).filter { !$0.isControl }
    }

    /// Mọi mục (kể cả điều khiển), chưa ghép giá trị `infoMap`. JS của `exploreUrl` thấy `infoMap` của nguồn (§11.3).
    func exploreEntriesIncludingControls(_ exploreUrl: String) throws -> [LegadoEngineExploreItem] {
        let trimmed = exploreUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        activateExploreInfo()
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
            return try labelled(entries(fromScriptResult: value))
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

    /// Đánh giá `viewName` (biểu thức JS) của điều khiển thành nhãn; lỗi ⇒ giữ `title`.
    private func labelled(_ items: [LegadoEngineExploreItem]) throws -> [LegadoEngineExploreItem] {
        var output = items
        for index in output.indices {
            guard let viewName = output[index].viewNameSource else { continue }
            output[index].label = try viewNameLabel(.string(viewName), fallback: output[index].title)
        }
        return output
    }

    static func entries(fromJSONItems items: [LegadoEngineJSON]) -> [LegadoEngineExploreItem] {
        var output: [LegadoEngineExploreItem] = []
        for item in items {
            guard let fields = item.objectEntries else {
                if case .string(let text) = item { output.append(contentsOf: Self.entries(fromText: text)) }
                continue
            }
            let type = (item["type"]?.scalarString ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let title = (item["title"]?.scalarString ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let style = item["style"]
            if let control = Self.controlKind(type) {
                let actionText = item["action"]?.scalarString.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                var entry = LegadoEngineExploreItem(
                    title: title, url: nil, kind: control, action: actionText.isEmpty ? nil : actionText,
                    chars: item["chars"]?.arrayValue?.map { $0.scalarString } ?? [],
                    defaultValue: item["default"].flatMap { $0.isNull ? nil : $0.scalarString },
                    style: LegadoFlexStyle.parse(style)
                )
                let viewName = item["viewName"]?.scalarString.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                entry.viewNameSource = viewName.isEmpty ? nil : viewName
                output.append(entry)
                continue
            }
            var url = item["url"].map { $0.isNull ? "" : $0.scalarString }?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let extras = fields.filter { requestOptionKeys.contains($0.key.lowercased()) }
            if !url.isEmpty, !extras.isEmpty, LegadoURLResolver.splitOption(url).option == nil {
                url += "," + LegadoEngineJSON.object(extras).compactText
            }
            let flex = LegadoFlexStyle.parse(style)
            output.append(LegadoEngineExploreItem(
                title: title,
                url: url.isEmpty || url == "null" || type == "title" ? nil : url,
                flexBasisPercent: flex.flexBasisPercent,
                flexGrow: flex.flexGrow,
                wrapBefore: flex.wrapBefore,
                style: flex
            ))
        }
        return output
    }

    /// `type` của mục → điều khiển (§11.2); mục thường/`title`/kiểu lạ ⇒ `nil` (hiển thị như mục thường nếu có `url`).
    static func controlKind(_ type: String) -> LegadoEngineExploreItem.Kind? {
        switch type {
        case "select": return .select
        case "toggle": return .toggle
        case "text", "input": return .text
        case "button": return .button
        default: return nil
        }
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
