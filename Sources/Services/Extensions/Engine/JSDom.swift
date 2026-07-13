import Foundation
import JavaScriptCore
import SwiftSoup

// MARK: - JSExport Protocols
//
// File này định nghĩa các cầu nối JSExport giúp export thư viện parse HTML SwiftSoup sang JavaScript.
// Mọi class triển khai bên dưới đều kế thừa protocol tương ứng để JSContext có thể gọi trực tiếp.
//
// Sơ đồ phân cấp cấu trúc DOM được ánh xạ sang JS:
// JSHtml (Html toàn cục) ──> JSDocument ──> JSElements (Danh sách) ──> JSElement (Phần tử)
//

/// Cầu nối cho JSHtml - Namespace "Html" toàn cục trong JS.
///
/// **Cách sử dụng trong JS:**
/// ```javascript
/// var doc = Html.parse("<html>...</html>");
/// var docWithBase = Html.parseWithBase("<html>...</html>", "https://example.com");
/// ```
@objc protocol JSHtmlExport: JSExport {
    static func parse(_ html: String) -> JSDocument
    static func parseWithBase(_ html: String, _ baseUri: String) -> JSDocument
    static func clean(_ html: String, _ tags: [String]) -> String
}

/// Cầu nối cho JSDocument - Đại diện cho toàn bộ tài liệu HTML được phân tích.
@objc protocol JSDocumentExport: JSExport {
    func select(_ selector: String) -> JSElements
    func text() -> String
    func html() -> String
    func body() -> JSElement?
    func title() -> String
}

/// Cầu nối cho JSElement - Đại diện cho một phần tử DOM đơn lẻ.
/// Hỗ trợ cả các hàm Getters (lấy thông tin) và Setters (chỉnh sửa nội dung).
@objc protocol JSElementExport: JSExport {
    // Getters
    func select(_ selector: String) -> JSElements
    func text() -> String
    func html() -> String
    func attr(_ name: String) -> String
    func ownText() -> String
    func data() -> String
    func tagName() -> String
    func id() -> String
    func className() -> String
    func hasClass(_ className: String) -> Bool
    func val() -> String
    func parent() -> JSElement?
    func children() -> JSElements
    func siblingElements() -> JSElements
    func nextElementSibling() -> JSElement?
    func previousElementSibling() -> JSElement?
    func remove()
    func outerHtml() -> String
    func hasAttr(_ name: String) -> Bool
    func absUrl(_ name: String) -> String
    
    // Setters (Chỉnh sửa DOM)
    func setAttr(_ name: String, _ value: String)
    func setText(_ value: String)
    func setHtml(_ value: String)
    func append(_ html: String)
    func prepend(_ html: String)
    func addClass(_ className: String)
    func removeClass(_ className: String)
}

/// Cầu nối cho JSElements - Đại diện cho danh sách các phần tử DOM.
///
/// **Cách duyệt mảng trong JS:**
/// ```javascript
/// // Cách 1: Duyệt qua forEach (được định nghĩa qua prototype bootstrap)
/// elements.forEach(function(el) { ... });
///
/// // Cách 2: Chuyển đổi thành Array JS native để sử dụng map/filter
/// var elArray = elements.array();
/// var texts = elArray.map(function(el) { return el.text(); });
/// ```
@objc protocol JSElementsExport: JSExport {
    func select(_ selector: String) -> JSElements
    func text() -> String
    func html() -> String
    func attr(_ name: String) -> String
    func size() -> Int
    func get(_ index: Int) -> JSElement?
    func first() -> JSElement?
    func last() -> JSElement?
    func hasClass(_ className: String) -> Bool
    func val() -> String
    func eq(_ index: Int) -> JSElements
    func remove()
    func eachText() -> [String]
    func eachAttr(_ name: String) -> [String]
    func array() -> [JSElement]
    var length: Int { get }
    func forEach(_ callback: JSValue)
}

// MARK: - Concrete Implementations

@objc public final class JSHtml: NSObject, JSHtmlExport {
    private static func fixUnclosedATags(_ html: String) -> String {
        let pattern = "(<a[^>]*class=\\s*[\"'](?:imgbox|img-box|cover|book-cover|bookcover|picbox|imagebox)[\"'][^>]*>\\s*<img[^>]*>)"
        if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
            let range = NSRange(location: 0, length: html.utf16.count)
            return regex.stringByReplacingMatches(in: html, options: [], range: range, withTemplate: "$1</a>")
        }
        return html
    }

    public static func parse(_ html: String) -> JSDocument {
        do {
            let fixedHtml = fixUnclosedATags(html)
            let doc = try SwiftSoup.parse(fixedHtml)
            cleanAds(from: doc)
            return JSDocument(doc)
        } catch {
            // print("JSHtml parse error: \(error)")
            return JSDocument(Document(""))
        }
    }
    
    public static func parseWithBase(_ html: String, _ baseUri: String) -> JSDocument {
        do {
            let fixedHtml = fixUnclosedATags(html)
            let doc = try SwiftSoup.parse(fixedHtml, baseUri)
            cleanAds(from: doc)
            return JSDocument(doc)
        } catch {
            // print("JSHtml parseWithBase error: \(error)")
            return JSDocument(Document(""))
        }
    }
    
    private static func cleanAds(from doc: Document) {
        let adSelectors = [
            "div.panel-g",
            "div.ads", "div.ad", "div.a_d", "div.gg-ad", "div.gg_ad", "div.mgid-widget",
            "div[class*=\"-ad-\"]", "div[id*=\"-ad-\"]",
            "div[class*=\"ad-container\"]", "div[class*=\"ad-wrapper\"]", "div[class*=\"ad-box\"]",
            "div[class*=\"ads-box\"]", "div[class*=\"ad-header\"]", "div[class*=\"ad-footer\"]",
            "div[class*=\"pop-ad\"]", "div[class*=\"float-ad\"]",
            "div[id*=\"google_ads_\"]", "div[id*=\"div-gpt-ad\"]",
            "iframe[id*=\"google_ads_\"]", "iframe[src*=\"googleads\"]", "iframe[src*=\"doubleclick\"]",
            "div[class*=\"mgid\"]", "div[id*=\"mgid\"]",
            "div[class*=\"taboola\"]", "div[id*=\"taboola\"]",
            "ins.adsbygoogle",
            "a[href*=\"erodalabs.com\"]",
            "a[href*=\"tip-top.one\"]",
            "a[href*=\"bet88\"]", "a[href*=\"w88\"]", "a[href*=\"fun88\"]", "a[href*=\"shopee.vn\"]", "a[href*=\"lazada.vn\"]"
        ]
        for selector in adSelectors {
            if let elements = try? doc.select(selector) {
                _ = try? elements.remove()
            }
        }
    }
    
    public static func clean(_ html: String, _ tags: [String]) -> String {
        do {
            let whitelist = Whitelist.none()
            for tag in tags {
                _ = try whitelist.addTags(tag)
            }
            return try SwiftSoup.clean(html, whitelist) ?? ""
        } catch {
            // print("JSHtml clean error: \(error)")
            return html
        }
    }
}

@objc public final class JSDocument: NSObject, JSDocumentExport {
    private let doc: Document
    
    init(_ doc: Document) {
        self.doc = doc
    }
    
    public func select(_ selector: String) -> JSElements {
        do {
            let elements = try doc.select(selector)
            return JSElements(elements)
        } catch {
            // print("JSDocument select error: \(error)")
            return JSElements(Elements())
        }
    }
    
    public func text() -> String {
        do {
            return try doc.text()
        } catch {
            return ""
        }
    }
    
    public func html() -> String {
        do {
            return try doc.html()
        } catch {
            return ""
        }
    }
    
    public func body() -> JSElement? {
        guard let bodyEl = doc.body() else { return nil }
        return JSElement(bodyEl)
    }
    
    public func title() -> String {
        do {
            return try doc.title()
        } catch {
            return ""
        }
    }
}

@objc public final class JSElement: NSObject, JSElementExport {
    private let element: Element?
    
    init(_ element: Element?) {
        self.element = element
    }
    
    public func select(_ selector: String) -> JSElements {
        guard let element = element else { return JSElements(Elements()) }
        do {
            let elements = try element.select(selector)
            return JSElements(elements)
        } catch {
            // print("JSElement select error: \(error)")
            return JSElements(Elements())
        }
    }
    
    public func text() -> String {
        guard let element = element else { return "" }
        do {
            return try element.text()
        } catch {
            return ""
        }
    }
    
    public func html() -> String {
        guard let element = element else { return "" }
        do {
            return try element.html()
        } catch {
            return ""
        }
    }
    
    public func attr(_ name: String) -> String {
        guard let element = element else { return "" }
        do {
            return try element.attr(name)
        } catch {
            return ""
        }
    }
    
    public func ownText() -> String {
        guard let element = element else { return "" }
        return element.ownText()
    }
    
    public func data() -> String {
        guard let element = element else { return "" }
        return element.data()
    }
    
    public func tagName() -> String {
        guard let element = element else { return "" }
        return element.tagName()
    }
    
    public func id() -> String {
        guard let element = element else { return "" }
        return element.id()
    }
    
    public func className() -> String {
        guard let element = element else { return "" }
        return (try? element.className()) ?? ""
    }
    
    public func hasClass(_ className: String) -> Bool {
        guard let element = element else { return false }
        return element.hasClass(className)
    }
    
    public func val() -> String {
        guard let element = element else { return "" }
        do {
            return try element.val()
        } catch {
            return ""
        }
    }
    
    public func parent() -> JSElement? {
        guard let element = element, let parentEl = element.parent() else { return nil }
        return JSElement(parentEl)
    }
    
    public func children() -> JSElements {
        guard let element = element else { return JSElements(Elements()) }
        return JSElements(element.children())
    }
    
    public func siblingElements() -> JSElements {
        guard let element = element else { return JSElements(Elements()) }
        return JSElements(element.siblingElements())
    }
    
    public func nextElementSibling() -> JSElement? {
        guard let element = element else { return nil }
        do {
            guard let nextEl = try element.nextElementSibling() else { return nil }
            return JSElement(nextEl)
        } catch {
            return nil
        }
    }
    
    public func previousElementSibling() -> JSElement? {
        guard let element = element else { return nil }
        do {
            guard let prevEl = try element.previousElementSibling() else { return nil }
            return JSElement(prevEl)
        } catch {
            return nil
        }
    }
    
    public func remove() {
        guard let element = element else { return }
        do {
            try element.remove()
        } catch {
            // print("JSElement remove error: \(error)")
        }
    }
    
    public func outerHtml() -> String {
        guard let element = element else { return "" }
        do {
            return try element.outerHtml()
        } catch {
            return ""
        }
    }
    
    public func hasAttr(_ name: String) -> Bool {
        guard let element = element else { return false }
        return element.hasAttr(name)
    }
    
    public func absUrl(_ name: String) -> String {
        guard let element = element else { return "" }
        do {
            return try element.absUrl(name)
        } catch {
            return ""
        }
    }
    
    public func setAttr(_ name: String, _ value: String) {
        guard let element = element else { return }
        _ = try? element.attr(name, value)
    }
    
    public func setText(_ value: String) {
        guard let element = element else { return }
        _ = try? element.text(value)
    }
    
    public func setHtml(_ value: String) {
        guard let element = element else { return }
        _ = try? element.html(value)
    }
    
    public func append(_ html: String) {
        guard let element = element else { return }
        _ = try? element.append(html)
    }
    
    public func prepend(_ html: String) {
        guard let element = element else { return }
        _ = try? element.prepend(html)
    }
    
    public func addClass(_ className: String) {
        guard let element = element else { return }
        _ = try? element.addClass(className)
    }
    
    public func removeClass(_ className: String) {
        guard let element = element else { return }
        _ = try? element.removeClass(className)
    }
}

@objc public final class JSElements: NSObject, JSElementsExport {
    private let elements: Elements
    
    init(_ elements: Elements) {
        self.elements = elements
    }
    
    public func select(_ selector: String) -> JSElements {
        do {
            let selected = try elements.select(selector)
            return JSElements(selected)
        } catch {
            // print("JSElements select error: \(error)")
            return JSElements(Elements())
        }
    }
    
    public func text() -> String {
        do {
            return try elements.text()
        } catch {
            return ""
        }
    }
    
    public func html() -> String {
        do {
            return try elements.html()
        } catch {
            return ""
        }
    }
    
    public func attr(_ name: String) -> String {
        do {
            return try elements.attr(name)
        } catch {
            return ""
        }
    }
    
    public func size() -> Int {
        return elements.size()
    }
    
    public func get(_ index: Int) -> JSElement? {
        guard index >= 0 && index < elements.size() else {
            return JSElement(nil)
        }
        return JSElement(elements.get(index))
    }
    
    public func first() -> JSElement? {
        guard let first = elements.first() else {
            return JSElement(nil)
        }
        return JSElement(first)
    }
    
    public func last() -> JSElement? {
        guard let last = elements.last() else {
            return JSElement(nil)
        }
        return JSElement(last)
    }
    
    public func hasClass(_ className: String) -> Bool {
        return elements.hasClass(className)
    }
    
    public func val() -> String {
        do {
            return try elements.val()
        } catch {
            return ""
        }
    }
    
    public func eq(_ index: Int) -> JSElements {
        guard index >= 0 && index < elements.size() else { return JSElements(Elements()) }
        let single = Elements([elements.get(index)])
        return JSElements(single)
    }
    
    public func remove() {
        do {
            try elements.remove()
        } catch {
            // print("JSElements remove error: \(error)")
        }
    }
    
    public func eachText() -> [String] {
        return elements.array().map { (try? $0.text()) ?? "" }
    }
    
    public func eachAttr(_ name: String) -> [String] {
        var list: [String] = []
        for el in elements.array() {
            if let val = try? el.attr(name) {
                list.append(val)
            }
        }
        return list
    }
    
    public func array() -> [JSElement] {
        return elements.array().map { JSElement($0) }
    }
    
    public var length: Int {
        return elements.size()
    }
    
    public func forEach(_ callback: JSValue) {
        let size = elements.size()
        for i in 0..<size {
            let item = JSElement(elements.get(i))
            callback.call(withArguments: [item, i, self])
        }
    }
}
