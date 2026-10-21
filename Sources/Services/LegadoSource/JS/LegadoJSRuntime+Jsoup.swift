import Foundation
import SwiftSoup

/// Phía Swift của shim `org.jsoup` (spec §6.8): thao tác trên phần tử SwiftSoup theo handle. Bộ chọn là CSS kiểu
/// jsoup của SwiftSoup; bộ chọn lỗi ⇒ danh sách rỗng.
extension LegadoJSRuntime {
    func nativeJsoup(_ command: String, _ arguments: LegadoJSArguments) throws -> String? {
        if command == "jsoup.parse" || command == "jsoup.fragment" {
            let html = text(of: arguments[0])
            let base = arguments.plainString(1) ?? ""
            let document: Document?
            if command == "jsoup.parse" {
                document = try? SwiftSoup.parse(html, base)
            } else {
                document = try? SwiftSoup.parseBodyFragment(html, base)
            }
            guard let document else { return "-1" }
            return String(register(document))
        }
        guard command.hasPrefix("el.") else { return nil }
        guard let handle = arguments.int(0), let element = element(handle: handle) else {
            throw LegadoJSNativeError("Phần tử HTML không còn hợp lệ")
        }
        switch command {
        case "el.select":
            let found = (try? element.select(text(of: arguments[1])).array()) ?? []
            return handles(found)
        case "el.text": return (try? element.text()) ?? ""
        case "el.ownText": return element.ownText()
        case "el.wholeText":
            return element.textNodes().map { $0.getWholeText() }.joined()
        case "el.html": return (try? element.html()) ?? ""
        case "el.outerHtml": return (try? element.outerHtml()) ?? ""
        case "el.data": return element.data()
        case "el.val": return (try? element.val()) ?? ""
        case "el.attr": return (try? element.attr(text(of: arguments[1]))) ?? ""
        case "el.setAttr":
            _ = try? element.attr(text(of: arguments[1]), text(of: arguments[2]))
            return ""
        case "el.hasAttr": return element.hasAttr(text(of: arguments[1])) ? "1" : ""
        case "el.absUrl": return (try? element.absUrl(text(of: arguments[1]))) ?? ""
        case "el.hasClass": return element.hasClass(text(of: arguments[1])) ? "1" : ""
        case "el.id": return element.id()
        case "el.className": return (try? element.className()) ?? ""
        case "el.tagName": return element.tagName()
        case "el.children": return handles(element.children().array())
        case "el.child":
            let children = element.children()
            guard let index = arguments.int(1), index >= 0, index < children.size() else { return "-1" }
            return String(register(children.get(index)))
        case "el.parent": return handle(element.parent())
        case "el.next": return handle((try? element.nextElementSibling()) ?? nil)
        case "el.prev": return handle((try? element.previousElementSibling()) ?? nil)
        case "el.byId": return handle((try? element.getElementById(text(of: arguments[1]))) ?? nil)
        case "el.byTag": return handles((try? element.getElementsByTag(text(of: arguments[1])).array()) ?? [])
        case "el.byClass": return handles((try? element.getElementsByClass(text(of: arguments[1])).array()) ?? [])
        case "el.remove":
            try? element.remove()
            return ""
        case "el.body": return handle(element.ownerDocument()?.body())
        case "el.head": return handle(element.ownerDocument()?.head())
        case "el.title": return (try? element.ownerDocument()?.title()) ?? ""
        default:
            return nil
        }
    }

    private func handle(_ element: Element?) -> String {
        guard let element else { return "-1" }
        return String(register(element))
    }

    private func handles(_ elements: [Element]) -> String {
        "[" + elements.map { String(register($0)) }.joined(separator: ",") + "]"
    }
}
