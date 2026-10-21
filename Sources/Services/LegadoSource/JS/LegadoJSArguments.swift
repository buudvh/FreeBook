import Foundation

/// Đối số của một lời gọi native từ bootstrap JS: mảng descriptor JSON (xem `LegadoJSBootstrap`).
/// Chuyển descriptor phần tử/byte sang giá trị Swift cần registry của runtime nên nằm ở `LegadoJSRuntime`.
struct LegadoJSArguments {
    let values: [LegadoEngineJSON]

    init(json: String) {
        values = LegadoEngineJSONParser.parse(json)?.arrayValue ?? []
    }

    var count: Int { values.count }

    subscript(index: Int) -> LegadoEngineJSON {
        index >= 0 && index < values.count ? values[index] : .null
    }

    func isNull(_ index: Int) -> Bool {
        self[index].isNull
    }

    func number(_ index: Int) -> Double? {
        guard let value = self[index].doubleValue, value.isFinite else { return nil }
        return value
    }

    func int(_ index: Int) -> Int? {
        guard let value = number(index), abs(value) < 9.0e15 else { return nil }
        return Int(value)
    }

    func bool(_ index: Int) -> Bool {
        switch self[index] {
        case .bool(let flag): return flag
        case .number(let value, _): return value != 0
        case .string(let text): return LegadoRuleValue.isTruthy(text)
        default: return false
        }
    }

    /// Chuỗi của đối số dạng chuỗi/số/bool; `nil` khi `null`/thiếu hoặc là object.
    func plainString(_ index: Int) -> String? {
        switch self[index] {
        case .string(let text): return text
        case .number, .bool: return self[index].scalarString
        default: return nil
        }
    }
}
