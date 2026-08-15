import Foundation

/// Chuẩn hoá link truyện để so khớp dedupe: bỏ scheme/host, đảm bảo bắt đầu bằng "/".
/// Dùng chung cho danh sách genres, discovery, search và suggest.
func normalizeLink(_ link: String) -> String {
    var clean = link.trimmingCharacters(in: .whitespacesAndNewlines)
    if clean.hasPrefix("http://") || clean.hasPrefix("https://") {
        if let range = clean.range(of: "://") {
            let afterScheme = clean[range.upperBound...]
            if let slashIndex = afterScheme.firstIndex(of: "/") {
                clean = String(afterScheme[slashIndex...])
            } else {
                clean = "/"
            }
        }
    }
    if !clean.hasPrefix("/") {
        clean = "/" + clean
    }
    return clean
}

/// Lọc bỏ kết quả thiếu name/link và loại bỏ trùng theo `normalizeLink`.
/// Dùng chung cho danh sách genres, discovery, search và suggest.
func filterAndDeduplicate(_ results: [ExtensionItemResult]) -> [ExtensionItemResult] {
    let filtered = results.filter { !$0.name.isEmpty && !$0.link.isEmpty }
    return filtered.reduce(into: [ExtensionItemResult]()) { acc, item in
        if !acc.contains(where: { normalizeLink($0.link) == normalizeLink(item.link) }) {
            acc.append(item)
        }
    }
}
