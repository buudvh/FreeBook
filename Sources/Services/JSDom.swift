import Foundation
import JavaScriptCore
import SwiftSoup

// MARK: - JSExport Protocols

@objc protocol JSHtmlExport: JSExport {
    static func parse(_ html: String) -> JSDocument
    static func clean(_ html: String, _ tags: [String]) -> String
}

@objc protocol JSDocumentExport: JSExport {
    func select(_ selector: String) -> JSElements
    func text() -> String
    func html() -> String
}

@objc protocol JSElementExport: JSExport {
    func select(_ selector: String) -> JSElements
    func text() -> String
    func html() -> String
    func attr(_ name: String) -> String
    func ownText() -> String
    func data() -> String
}

@objc protocol JSElementsExport: JSExport {
    func select(_ selector: String) -> JSElements
    func text() -> String
    func html() -> String
    func attr(_ name: String) -> String
    func size() -> Int
    func get(_ index: Int) -> JSElement?
    func first() -> JSElement?
    func last() -> JSElement?
}

// MARK: - Concrete Implementations

@objc public final class JSHtml: NSObject, JSHtmlExport {
    public static func parse(_ html: String) -> JSDocument {
        do {
            let doc = try SwiftSoup.parse(html)
            return JSDocument(doc)
        } catch {
            print("JSHtml parse error: \(error)")
            return JSDocument(Document(""))
        }
    }
    
    public static func clean(_ html: String, _ tags: [String]) -> String {
        do {
            let whitelist = Whitelist()
            for tag in tags {
                _ = try whitelist.addTags(tag)
            }
            return try SwiftSoup.clean(html, whitelist) ?? ""
        } catch {
            print("JSHtml clean error: \(error)")
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
            print("JSDocument select error: \(error)")
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
}

@objc public final class JSElement: NSObject, JSElementExport {
    private let element: Element
    
    init(_ element: Element) {
        self.element = element
    }
    
    public func select(_ selector: String) -> JSElements {
        do {
            let elements = try element.select(selector)
            return JSElements(elements)
        } catch {
            print("JSElement select error: \(error)")
            return JSElements(Elements())
        }
    }
    
    public func text() -> String {
        return element.text()
    }
    
    public func html() -> String {
        do {
            return try element.html()
        } catch {
            return ""
        }
    }
    
    public func attr(_ name: String) -> String {
        return element.attr(name)
    }
    
    public func ownText() -> String {
        return element.ownText()
    }
    
    public func data() -> String {
        do {
            return try element.data()
        } catch {
            return ""
        }
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
            print("JSElements select error: \(error)")
            return JSElements(Elements())
        }
    }
    
    public func text() -> String {
        return elements.text()
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
        guard index >= 0 && index < elements.size() else { return nil }
        return JSElement(elements.get(index))
    }
    
    public func first() -> JSElement? {
        guard let first = elements.first() else { return nil }
        return JSElement(first)
    }
    
    public func last() -> JSElement? {
        guard let last = elements.last() else { return nil }
        return JSElement(last)
    }
}
