import Foundation
import JavaScriptCore
import SwiftSoup

/// Chuyển giá trị qua ranh giới Swift↔JS bằng descriptor JSON (xem `LegadoJSBootstrap`), và đổi descriptor thành
/// chuỗi/byte/nội dung cho các hàm native.
extension LegadoJSRuntime {
    // MARK: - Swift → JS

    /// Descriptor của một nội dung: phần tử HTML được đăng ký handle; nút XPath đổi thành HTML.
    func descriptor(for node: LegadoContentNode) -> LegadoEngineJSON {
        switch node {
        case .null:
            return .null
        case .string(let text):
            return .string(text)
        case .html(let element):
            let handle = register(element)
            return .object([(key: "$el", value: .number(Double(handle), String(handle)))])
        case .xpath(let xpathNode):
            return .string(xpathNode.outerHTML)
        case .json(let value):
            return .object([(key: "$json", value: value)])
        case .regexMatch(let groups):
            return .object([(key: "$arr", value: .strings(groups))])
        case .list(let items):
            return .object([(key: "$arr", value: .array(items.map { descriptor(for: $0) }))])
        }
    }

    /// Giá trị JS của một nội dung (chuỗi đi đường tắt, không qua JSON).
    func importValue(_ node: LegadoContentNode) -> JSValue {
        switch node {
        case .null:
            return JSValue(nullIn: context)
        case .string(let text):
            return JSValue(object: text, in: context) ?? undefinedValue
        default:
            let text = descriptor(for: node).compactText
            guard let importer = context.objectForKeyedSubscript("__lgImport"),
                  let value = importer.call(withArguments: [text]) else { return undefinedValue }
            return value
        }
    }

    // MARK: - JS → Swift

    /// Kết quả một đoạn JS thành nội dung (spec §2.14): `undefined`/`null` ⇒ `.null`, chuỗi ⇒ `.string`, số/bool ⇒ chuỗi,
    /// mảng ⇒ `.list`, object ⇒ `.json`, phần tử shim ⇒ `.html`.
    func export(_ value: JSValue?) -> LegadoContentNode {
        guard let value, !value.isUndefined, !value.isNull else { return .null }
        if value.isString { return .string(value.toString() ?? "") }
        guard let text = runExporter(value), let json = LegadoEngineJSONParser.parse(text) else {
            return .string(value.toString() ?? "")
        }
        return content(fromDescriptor: json)
    }

    private func runExporter(_ value: JSValue) -> String? {
        guard let exporter = context.objectForKeyedSubscript("__lgExport"),
              let result = exporter.call(withArguments: [value]),
              result.isString else { return nil }
        return result.toString()
    }

    func content(fromDescriptor descriptor: LegadoEngineJSON) -> LegadoContentNode {
        switch descriptor {
        case .null:
            return .null
        case .string(let text):
            return .string(text)
        case .number, .bool:
            return .string(descriptor.scalarString)
        case .array(let items):
            return .list(items.map { content(fromDescriptor: $0) })
        case .object:
            if let handle = descriptor["$el"]?.doubleValue {
                guard handle.isFinite, abs(handle) < 1.0e9, let element = element(handle: Int(handle)) else { return .null }
                return .html(element)
            }
            if let items = descriptor["$arr"]?.arrayValue {
                return .list(items.map { content(fromDescriptor: $0) })
            }
            if let json = descriptor["$json"] {
                return .json(json)
            }
            if let hex = descriptor["$bytes"]?.stringValue {
                return .string(String(decoding: Self.bytes(fromHex: hex), as: UTF8.self))
            }
            if let response = descriptor["$resp"] {
                // Đối tượng phản hồi như chuỗi = thân (`toString()`), spec §6.4.1.
                return .string(response["body"]?.scalarString ?? "")
            }
            return .json(descriptor)
        }
    }

    /// Chuỗi của một đối số: chuỗi/số/bool như JS `String(x)`, byte ⇒ UTF-8, phần tử ⇒ outer HTML, object ⇒ JSON.
    func text(of descriptor: LegadoEngineJSON) -> String {
        switch descriptor {
        case .null: return ""
        case .string(let text): return text
        case .number, .bool: return descriptor.scalarString
        case .array: return descriptor.compactText
        case .object:
            if let hex = descriptor["$bytes"]?.stringValue {
                return String(decoding: Self.bytes(fromHex: hex), as: UTF8.self)
            }
            if let response = descriptor["$resp"] {
                return response["body"]?.scalarString ?? ""
            }
            switch content(fromDescriptor: descriptor) {
            case .html(let element): return (try? element.outerHtml()) ?? ""
            case .json(let value): return value.scalarString
            case let other: return other.displayText
            }
        }
    }

    /// Byte của một đối số: `{"$bytes"}`, mảng số (byte kiểu Java), hoặc chuỗi (UTF-8).
    func bytes(of descriptor: LegadoEngineJSON) -> Data? {
        switch descriptor {
        case .null:
            return nil
        case .string(let text):
            return Data(text.utf8)
        case .number, .bool:
            return Data(descriptor.scalarString.utf8)
        case .array(let items):
            return Self.bytes(fromNumbers: items)
        case .object:
            if let hex = descriptor["$bytes"]?.stringValue { return Data(Self.bytes(fromHex: hex)) }
            if let items = descriptor["$arr"]?.arrayValue, items.allSatisfy({ $0.doubleValue != nil }) {
                return Self.bytes(fromNumbers: items)
            }
            return Data(text(of: descriptor).utf8)
        }
    }

    /// Đối số có phải mảng byte không (để phân biệt `bytes` với chuỗi base64/hex khi giải mã).
    func isByteArray(_ descriptor: LegadoEngineJSON) -> Bool {
        if descriptor["$bytes"] != nil { return true }
        if let items = descriptor["$arr"]?.arrayValue, !items.isEmpty, items.allSatisfy({ $0.doubleValue != nil }) { return true }
        if case .array(let items) = descriptor, !items.isEmpty, items.allSatisfy({ $0.doubleValue != nil }) { return true }
        return false
    }

    /// Nội dung của đối số `content` của `java.getString`… (`nil` = dùng nội dung hiện hành).
    func contentArgument(_ descriptor: LegadoEngineJSON) -> LegadoContentNode? {
        if descriptor.isNull { return nil }
        return content(fromDescriptor: descriptor)
    }

    // MARK: - Handle phần tử

    func register(_ element: Element) -> Int {
        elementHandles.append(element)
        return elementHandles.count - 1
    }

    func element(handle: Int) -> Element? {
        guard handle >= 0, handle < elementHandles.count else { return nil }
        return elementHandles[handle]
    }

    // MARK: - Byte

    static func bytes(fromHex hex: String) -> [UInt8] {
        let digits = Array(hex.utf8).compactMap { hexValue($0) }
        var output: [UInt8] = []
        output.reserveCapacity(digits.count / 2)
        var index = 0
        while index + 1 < digits.count {
            output.append(digits[index] << 4 | digits[index + 1])
            index += 2
        }
        return output
    }

    static func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    private static func hexValue(_ byte: UInt8) -> UInt8? {
        switch byte {
        case 48...57: return byte - 48
        case 65...70: return byte - 55
        case 97...102: return byte - 87
        default: return nil
        }
    }

    private static func bytes(fromNumbers items: [LegadoEngineJSON]) -> Data {
        Data(items.map { item -> UInt8 in
            let value = item.doubleValue ?? 0
            guard value.isFinite, abs(value) < 1.0e9 else { return 0 }
            return UInt8(truncatingIfNeeded: Int(value))
        })
    }
}
