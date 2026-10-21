import Foundation

/// Tài liệu HTML phân tích bằng libxml2 hệ thống để chạy XPath cho nguồn Legado.
///
/// Không `import` module nào: các hàm C đến từ bridging header (`LegadoLibXML2.h`). Cũng không có
/// `#if canImport` hay đường thay thế — thiếu libxml2 phải là lỗi biên dịch, không phải XPath im lặng trả rỗng.
///
/// Một instance chỉ dùng trên một thread tại một thời điểm (libxml2 không khoá document). Mọi con trỏ nút lấy ra
/// từ đây chỉ sống khi instance còn sống — `LegadoXPathNode` giữ tham chiếu mạnh tới document vì lý do đó.
final class LegadoXPathDocument {
    /// Một kết quả XPath: nút (phần tử) hoặc giá trị chuỗi (nút chữ, thuộc tính, số, bool, chuỗi).
    enum Item {
        case node(xmlNodePtr)
        case text(String)
    }

    private static let parserInitialization: Void = {
        xmlInitParser()
    }()

    private let document: htmlDocPtr

    /// Trả `nil` khi chuỗi rỗng hoặc libxml2 không dựng được cây.
    init?(html: String) {
        _ = Self.parserInitialization
        let bytes = Array(html.utf8)
        guard !bytes.isEmpty else { return nil }
        let options = Int32(truncatingIfNeeded:
            HTML_PARSE_RECOVER.rawValue
                | HTML_PARSE_NOERROR.rawValue
                | HTML_PARSE_NOWARNING.rawValue
                | HTML_PARSE_NONET.rawValue
        )
        let parsed: htmlDocPtr? = bytes.withUnsafeBufferPointer { buffer in
            buffer.baseAddress?.withMemoryRebound(to: CChar.self, capacity: buffer.count) { pointer in
                htmlReadMemory(pointer, Int32(buffer.count), nil, "UTF-8", options)
            }
        }
        guard let parsed else { return nil }
        document = parsed
    }

    deinit {
        xmlFreeDoc(document)
    }

    /// Chạy biểu thức XPath trên gốc tài liệu, trả giá trị chuỗi của từng kết quả.
    /// Biểu thức sai cú pháp trả mảng rỗng (libxml2 trả `NULL`).
    func evaluateStrings(_ expression: String) -> [String] {
        evaluate(expression, at: nil).map { item in
            switch item {
            case .node(let node): return Self.content(of: node)
            case .text(let text): return text
            }
        }
    }

    /// Chạy XPath với nút ngữ cảnh `node` (`nil` = gốc tài liệu). Phần tử trả `.node`, mọi loại khác trả `.text`.
    func evaluate(_ expression: String, at node: xmlNodePtr?) -> [Item] {
        guard let context = xmlXPathNewContext(document) else { return [] }
        defer { xmlXPathFreeContext(context) }
        if let node {
            context.pointee.node = node
        }

        let evaluated: xmlXPathObjectPtr? = expression.withCString { cString in
            cString.withMemoryRebound(to: xmlChar.self, capacity: strlen(cString) + 1) { xpath in
                xmlXPathEval(xpath, context)
            }
        }
        guard let object = evaluated else { return [] }
        defer { xmlXPathFreeObject(object) }

        switch object.pointee.type {
        case XPATH_NODESET:
            guard let nodeSet = object.pointee.nodesetval, let nodes = nodeSet.pointee.nodeTab else { return [] }
            var items: [Item] = []
            for index in 0..<Int(nodeSet.pointee.nodeNr) {
                guard let found = nodes[index] else { continue }
                if found.pointee.type == XML_ELEMENT_NODE || found.pointee.type == XML_HTML_DOCUMENT_NODE
                    || found.pointee.type == XML_DOCUMENT_NODE {
                    items.append(.node(found))
                } else {
                    items.append(.text(Self.content(of: found)))
                }
            }
            return items
        case XPATH_STRING:
            guard let value = object.pointee.stringval else { return [] }
            return [.text(String(cString: value))]
        case XPATH_NUMBER:
            return [.text(LegadoEngineJSON.formatNumber(object.pointee.floatval, raw: ""))]
        case XPATH_BOOLEAN:
            return [.text(object.pointee.boolval != 0 ? "true" : "false")]
        default:
            return []
        }
    }

    /// Nút đại diện khi tài liệu được dựng từ HTML của **một** phần tử: phần tử đầu tiên trong `body`
    /// (libxml2 luôn bọc mảnh HTML vào `html/body`). Tài liệu đầy đủ thì trả gốc.
    func fragmentRoot(expectedTag: String?) -> xmlNodePtr? {
        guard let root = xmlDocGetRootElement(document) else { return nil }
        let tag = expectedTag?.lowercased() ?? ""
        if tag == "html" || tag.isEmpty { return root }
        var candidates: [xmlNodePtr] = [root]
        while !candidates.isEmpty {
            let current = candidates.removeFirst()
            if Self.name(of: current) == tag, tag == "body" || tag == "head" { return current }
            if Self.name(of: current) == "body" {
                return Self.firstElementChild(of: current) ?? current
            }
            var child = current.pointee.children
            while let next = child {
                if next.pointee.type == XML_ELEMENT_NODE { candidates.append(next) }
                child = next.pointee.next
            }
        }
        return root
    }

    /// HTML/XML của một nút (dùng khi rule con không phải XPath cần dựng lại bằng SwiftSoup).
    func serialize(_ node: xmlNodePtr) -> String {
        guard let buffer = xmlBufferCreate() else { return "" }
        defer { xmlBufferFree(buffer) }
        _ = xmlNodeDump(buffer, document, node, 0, 0)
        guard let content = xmlBufferContent(buffer) else { return "" }
        return String(cString: content)
    }

    static func content(of node: xmlNodePtr) -> String {
        guard let raw = xmlNodeGetContent(node) else { return "" }
        defer { xmlFree(raw) }
        return String(cString: raw)
    }

    static func name(of node: xmlNodePtr) -> String {
        guard let name = node.pointee.name else { return "" }
        return String(cString: name).lowercased()
    }

    private static func firstElementChild(of node: xmlNodePtr) -> xmlNodePtr? {
        var child = node.pointee.children
        while let next = child {
            if next.pointee.type == XML_ELEMENT_NODE { return next }
            child = next.pointee.next
        }
        return nil
    }
}
