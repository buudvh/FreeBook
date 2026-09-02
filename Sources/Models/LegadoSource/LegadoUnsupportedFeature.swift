import Foundation

/// Tính năng của nguồn Legado mà FreeBook **chưa** hỗ trợ.
///
/// Nguyên tắc của phân hệ: không im lặng trả rỗng. Mỗi lần engine gặp cú pháp ngoài phạm vi, nó ghi
/// một case ở đây để màn hình quản lý nguồn hiện đúng lý do, và để người dùng biết nên bỏ nguồn nào.
public enum LegadoUnsupportedFeature: String, CaseIterable {
    case webViewRule = "webView"
    case webJsRule = "@webjs:"
    case login = "đăng nhập"
    case fontDecode = "queryTTF/replaceFont"
    case imageDecode = "imageDecode"
    case payAction = "payAction"
    case rhinoJavaPackage = "java.util/java.io/java.security"
    case nonTextSource = "loại nguồn không phải truyện chữ"
    case xpathBeyondSubset = "XPath ngoài tập con"

    public var explanation: String {
        switch self {
        case .webViewRule:
            return "Nguồn cần nạp trang bằng WebView (tuỳ chọn `webView` trong URL)."
        case .webJsRule:
            return "Nguồn dùng rule `@webjs:` chạy trong WebView."
        case .login:
            return "Nguồn yêu cầu đăng nhập (`loginUrl`/`loginUi`/`loginCheckJs`)."
        case .fontDecode:
            return "Nguồn làm rối chữ bằng font riêng, cần `queryTTF`/`replaceFont`."
        case .imageDecode:
            return "Nguồn mã hoá ảnh, cần `imageDecode`."
        case .payAction:
            return "Chương cần mua (`payAction`)."
        case .rhinoJavaPackage:
            return "Script dùng thẳng lớp Java (`java.util.Date`…), chỉ Rhino làm được."
        case .nonTextSource:
            return "Chỉ hỗ trợ nguồn truyện chữ (`bookSourceType == 0`)."
        case .xpathBeyondSubset:
            return "Biểu thức XPath vượt tập con được hỗ trợ."
        }
    }

    /// Quét tĩnh một nguồn để biết trước nó cần gì — chạy lúc import, không cần gọi mạng.
    public static func scan(_ source: LegadoBookSource) -> Set<LegadoUnsupportedFeature> {
        var found: Set<LegadoUnsupportedFeature> = []
        if !source.isTextSource { found.insert(.nonTextSource) }
        if !(source.loginUrl ?? "").isEmpty || !(source.loginUi ?? "").isEmpty
            || !(source.loginCheckJs ?? "").isEmpty {
            found.insert(.login)
        }
        if !(source.ruleContent.imageDecode ?? "").isEmpty { found.insert(.imageDecode) }
        if !(source.ruleContent.payAction ?? "").isEmpty { found.insert(.payAction) }

        let haystack = allRuleStrings(source)
        for text in haystack {
            let lower = text.lowercased()
            if lower.contains("\"webview\"") || lower.contains("'webview'") {
                found.insert(.webViewRule)
            }
            if lower.contains("@webjs:") { found.insert(.webJsRule) }
            if text.contains("queryTTF") || text.contains("replaceFont") {
                found.insert(.fontDecode)
            }
            if text.range(of: #"\bjava\.(util|io|security|lang|net|text|math)\b"#,
                          options: .regularExpression) != nil {
                found.insert(.rhinoJavaPackage)
            }
        }
        return found
    }

    private static func allRuleStrings(_ source: LegadoBookSource) -> [String] {
        var list: [String?] = [source.searchUrl, source.exploreUrl, source.coverDecodeJs]
        let search = source.ruleSearch
        let explore = source.ruleExplore
        for rule in [search, explore] {
            list.append(contentsOf: [
                rule.bookList, rule.name, rule.author, rule.intro, rule.kind,
                rule.lastChapter, rule.updateTime, rule.bookUrl, rule.coverUrl, rule.wordCount
            ])
        }
        let info = source.ruleBookInfo
        list.append(contentsOf: [
            info.initRule, info.name, info.author, info.intro, info.kind, info.lastChapter,
            info.updateTime, info.coverUrl, info.tocUrl, info.wordCount, info.downloadUrls
        ])
        let toc = source.ruleToc
        list.append(contentsOf: [
            toc.chapterList, toc.chapterName, toc.chapterUrl, toc.isVolume, toc.isVip,
            toc.isPay, toc.updateTime, toc.nextTocUrl, toc.preUpdateJs, toc.formatJs
        ])
        let content = source.ruleContent
        list.append(contentsOf: [
            content.content, content.subContent, content.title, content.nextContentUrl,
            content.replaceRegex, content.sourceRegex, content.webJs
        ])
        return list.compactMap { $0 }
    }
}
