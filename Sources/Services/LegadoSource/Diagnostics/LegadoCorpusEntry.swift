import Foundation

/// Lối vào chuỗi nghiệm thu của một nguồn, suy từ `ruleSearch.checkKeyWord` (spec §5.10) và rule có sẵn.
///
/// Dạng của `checkKeyWord` (spec §5.10, theo `debugHelp.md`): `++url` = gỡ lỗi mục lục, `--url` = gỡ lỗi nội dung,
/// URL trần = trang sách, `tên::url` = khám phá, còn lại = từ khoá. Thiếu `checkKeyWord` ⇒ từ khoá mặc định của lượt
/// chạy. Nguồn không có rule tìm kiếm thì đi Khám phá **qua danh mục của facade** (`genre`) — đúng đường tab Khám phá:
/// khoá phụ của mục dạng mảng JSON (`webView`/`method`/`body`…) chỉ được gộp vào option URL ở đó.
enum LegadoCorpusEntry: Sendable, Equatable {
    case keyword(String)
    case explore(url: String)
    /// Danh mục khám phá lấy qua `SourceRuntime.home`/`genre` rồi mở mục đầu tiên.
    case catalogExplore
    case bookURL(String)
    case tocURL(String)
    case contentURL(String)
    /// Không có lối vào dùng được (không rule tìm kiếm, không mục khám phá).
    case unavailable

    var modeName: String {
        switch self {
        case .keyword: return "keyword"
        case .explore: return "explore"
        case .catalogExplore: return "catalogExplore"
        case .bookURL: return "bookUrl"
        case .tocURL: return "tocUrl"
        case .contentURL: return "contentUrl"
        case .unavailable: return "-"
        }
    }

    /// Chuỗi ghi vào báo cáo: từ khoá cắt ngắn, URL qua redactor (giá trị query thành `…`).
    var reportQuery: String {
        switch self {
        case .keyword(let keyword):
            return ExtensionDebugRedactor.truncate(keyword, limit: 100)
        case .explore(let url), .bookURL(let url), .tocURL(let url), .contentURL(let url):
            return LegadoCorpusErrorClassifier.redactURL(url)
        case .catalogExplore, .unavailable:
            return ""
        }
    }

    static func resolve(
        checkKeyWord: String,
        fallbackKeyword: String,
        hasSearchRules: Bool,
        hasExploreRules: Bool
    ) -> LegadoCorpusEntry {
        let check = checkKeyWord.trimmingCharacters(in: .whitespacesAndNewlines)
        if !check.isEmpty, let debugEntry = debugEntry(from: check) {
            return debugEntry
        }
        if hasSearchRules {
            return .keyword(check.isEmpty ? fallbackKeyword : check)
        }
        return hasExploreRules ? .catalogExplore : .unavailable
    }

    /// Ba tiền tố gỡ lỗi + URL trần. `nil` ⇒ `checkKeyWord` là từ khoá thường.
    private static func debugEntry(from check: String) -> LegadoCorpusEntry? {
        if check.hasPrefix("++") {
            let url = String(check.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
            return url.isEmpty ? nil : .tocURL(url)
        }
        if check.hasPrefix("--") {
            let url = String(check.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
            return url.isEmpty ? nil : .contentURL(url)
        }
        if let range = check.range(of: "::") {
            let url = String(check[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            return url.isEmpty ? nil : .explore(url: url)
        }
        let lowered = check.lowercased()
        if lowered.hasPrefix("http://") || lowered.hasPrefix("https://") {
            return .bookURL(check)
        }
        return nil
    }
}
