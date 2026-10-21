import Foundation

/// Tài liệu HTML phân tích bằng libxml2 hệ thống để chạy XPath cho nguồn Legado.
///
/// Không `import` module nào: các hàm C đến từ bridging header (`LegadoLibXML2.h`). Cũng không có
/// `#if canImport` hay đường thay thế — thiếu libxml2 phải là lỗi biên dịch, không phải XPath im lặng trả rỗng.
///
/// Một instance chỉ dùng trên một thread tại một thời điểm (libxml2 không khoá document).
final class LegadoXPathDocument {
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
        guard let context = xmlXPathNewContext(document) else { return [] }
        defer { xmlXPathFreeContext(context) }

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
            return (0..<Int(nodeSet.pointee.nodeNr)).compactMap { index in
                nodes[index].map(Self.content(of:))
            }
        case XPATH_STRING:
            guard let value = object.pointee.stringval else { return [] }
            return [String(cString: value)]
        case XPATH_NUMBER:
            return [String(object.pointee.floatval)]
        case XPATH_BOOLEAN:
            return [object.pointee.boolval != 0 ? "true" : "false"]
        default:
            return []
        }
    }

    private static func content(of node: xmlNodePtr) -> String {
        guard let raw = xmlNodeGetContent(node) else { return "" }
        defer { xmlFree(raw) }
        return String(cString: raw)
    }
}
