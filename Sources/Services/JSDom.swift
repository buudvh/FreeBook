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
    func body() -> JSElement?
    func title() -> String
}

@objc protocol JSElementExport: JSExport {
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
    func hasClass(_ className: String) -> Bool
    func val() -> String
    func eq(_ index: Int) -> JSElements
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
            let whitelist = try Whitelist.none()
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
        do {
            return try element.text()
        } catch {
            return ""
        }
    }
    
    public func html() -> String {
        do {
            return try element.html()
        } catch {
            return ""
        }
    }
    
    public func attr(_ name: String) -> String {
        do {
            return try element.attr(name)
        } catch {
            return ""
        }
    }
    
    public func ownText() -> String {
        do {
            return try element.ownText()
        } catch {
            return ""
        }
    }
    
    public func data() -> String {
        return element.data()
    }
    
    public func tagName() -> String {
        return element.tagName()
    }
    
    public func id() -> String {
        return element.id()
    }
    
    public func className() -> String {
        return element.className()
    }
    
    public func hasClass(_ className: String) -> Bool {
        return element.hasClass(className)
    }
    
    public func val() -> String {
        do {
            return try element.val()
        } catch {
            return ""
        }
    }
    
    public func parent() -> JSElement? {
        guard let parentEl = element.parent() else { return nil }
        return JSElement(parentEl)
    }
    
    public func children() -> JSElements {
        return JSElements(element.children())
    }
    
    public func siblingElements() -> JSElements {
        return JSElements(element.siblingElements())
    }
    
    public func nextElementSibling() -> JSElement? {
        do {
            guard let nextEl = try element.nextElementSibling() else { return nil }
            return JSElement(nextEl)
        } catch {
            return nil
        }
    }
    
    public func previousElementSibling() -> JSElement? {
        do {
            guard let prevEl = try element.previousElementSibling() else { return nil }
            return JSElement(prevEl)
        } catch {
            return nil
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
        let single = Elements(elements.get(index))
        return JSElements(single)
    }
}
