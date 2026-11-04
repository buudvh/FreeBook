import Foundation

/// Phía Swift của `java.util.zip.*` giả lập (spec §6.9, script `streams`), giải bằng `LegadoInflate`:
/// - `inflate` `[byte, 'raw'|'zlib'|'gzip']` ⇒ hex của dữ liệu đã giải;
/// - `inflateUsed` cùng đối số ⇒ JSON `{"hex", "used"}`, `used` = số byte vào đã dùng (cho `Inflater.getRemaining()`).
extension LegadoJSRuntime {
    func nativeInflate(_ command: String, _ arguments: LegadoJSArguments) throws -> String? {
        guard command == "inflate" || command == "inflateUsed" else { return nil }
        let name = text(of: arguments[1])
        guard let format = LegadoInflate.Format(rawValue: name) else {
            throw LegadoJSNativeError("Giải nén: dạng lạ \(name)")
        }
        let outcome = try LegadoInflate.inflate(bytes(of: arguments[0]) ?? Data(), format: format)
        let hex = Self.inflatedHex(outcome.output)
        guard command == "inflateUsed" else { return hex }
        return LegadoEngineJSON.object([
            (key: "hex", value: .string(hex)),
            (key: "used", value: .fromNumber(Double(outcome.consumed)))
        ]).compactText
    }

    /// Hex của đầu ra giải nén (có thể vài MiB): bảng tra thay cho `String(format:)` từng byte của `hex(_:)`.
    private static func inflatedHex(_ data: Data) -> String {
        let digits = Array("0123456789abcdef".utf8)
        var characters: [UInt8] = []
        characters.reserveCapacity(data.count * 2)
        for byte in data {
            characters.append(digits[Int(byte >> 4)])
            characters.append(digits[Int(byte & 0x0F)])
        }
        return String(decoding: characters, as: UTF8.self)
    }
}
