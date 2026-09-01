import Foundation

/// Một mục Khám Phá của nguồn Legado (`ExploreKind.kt`).
///
/// `exploreUrl` có **ba** dạng (`help/source/BookSourceExtensions.kt:44-113`):
/// mảng JSON `ExploreKind[]`, các dòng `tên::url` cắt bằng `(&&|\n)+`, hoặc `@js:`/`<js>` sinh ra một
/// trong hai dạng trên. Chỉ `type == "url"` được hỗ trợ; `text/button/toggle/select` là UI lọc động
/// riêng của Legado nên bị bỏ qua.
public struct LegadoExploreKind {
    public let title: String
    public let url: String
    public let type: String

    public init(title: String, url: String, type: String = "url") {
        self.title = title
        self.url = url
        self.type = type
    }

    public var isSupported: Bool {
        type == "url" && !url.isEmpty
    }

    /// Phân tích chuỗi `exploreUrl` đã qua bước JS (nếu có) thành danh sách mục.
    public static func parse(_ raw: String) -> [LegadoExploreKind] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        if trimmed.hasPrefix("["), let list = LegadoJSON.array(trimmed) {
            return list.compactMap { item in
                guard let dict = item as? [String: Any] else { return nil }
                let title = LegadoJSON.string(dict["title"]) ?? ""
                let url = LegadoJSON.string(dict["url"]) ?? ""
                let type = LegadoJSON.string(dict["type"]) ?? "url"
                guard !title.isEmpty else { return nil }
                return LegadoExploreKind(title: title, url: url, type: type)
            }
        }

        // Cắt theo `&&` hoặc xuống dòng, giống regex `(&&|\n)+` của Legado.
        var kinds: [LegadoExploreKind] = []
        let separators = CharacterSet(charactersIn: "\n\r")
        for block in trimmed.replacingOccurrences(of: "&&", with: "\n")
            .components(separatedBy: separators) {
            let line = block.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            guard let range = line.range(of: "::") else {
                // Không có `::` ⇒ cả dòng là tiêu đề không có URL, Legado vẫn tạo mục rỗng.
                kinds.append(LegadoExploreKind(title: line, url: ""))
                continue
            }
            let title = String(line[line.startIndex..<range.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let url = String(line[range.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            kinds.append(LegadoExploreKind(title: title.isEmpty ? url : title, url: url))
        }
        return kinds
    }
}
