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
///
/// Giữ phần tử **đầu tiên** của mỗi khoá đã chuẩn hoá, đúng thứ tự gốc. Tra `Set` nên O(n) và
/// `normalizeLink` chỉ chạy một lần mỗi phần tử — bản `reduce` + `contains(where:)` cũ là O(n²) và
/// chuẩn hoá lại cả hai vế ở mọi cặp.
func filterAndDeduplicate(_ results: [ExtensionItemResult]) -> [ExtensionItemResult] {
    var seen = Set<String>()
    var output: [ExtensionItemResult] = []
    output.reserveCapacity(results.count)
    for item in results where !item.name.isEmpty && !item.link.isEmpty {
        if seen.insert(normalizeLink(item.link)).inserted {
            output.append(item)
        }
    }
    return output
}
