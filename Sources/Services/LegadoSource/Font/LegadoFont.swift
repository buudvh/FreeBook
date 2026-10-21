import Foundation
import CoreGraphics
import CoreText
import CryptoKit

/// Một font đã nạp cho `java.queryTTF`/`queryBase64TTF`/`replaceFont` (spec §14.1).
///
/// "Dấu vân tay" glyph = chuỗi lệnh path (`M/L/Q/C/Z` + toạ độ chuẩn hoá theo `unitsPerEm`, làm tròn tới 1/1000 em)
/// lấy bằng CoreText (`CTFontCreatePathForGlyph`, chạy cả `glyf` lẫn CFF), băm SHA-256. Glyph không có nét ⇒ vân tay
/// đặc biệt `empty`. An toàn đa luồng (đệm vân tay có khoá); font giống hệt byte được dùng chung trong tiến trình.
final class LegadoFont: @unchecked Sendable {
    static let emptyFingerprint = "empty"

    let tables: LegadoFontTables
    private let font: CTFont
    private let lock = NSLock()
    private var fingerprints: [UInt16: String] = [:]
    private var reverse: [String: UInt32]?

    private static let cacheLock = NSLock()
    private static var cache: [String: LegadoFont] = [:]
    private static var cacheOrder: [String] = []

    private init?(data: Data) {
        guard let tables = LegadoFontTables(data: data), let provider = CGDataProvider(data: data as CFData),
              let graphicsFont = CGFont(provider) else { return nil }
        self.tables = tables
        font = CTFontCreateWithGraphicsFont(graphicsFont, CGFloat(tables.unitsPerEm), nil, nil)
    }

    /// Nạp (hoặc lấy lại từ đệm tiến trình, tối đa 4 font) theo băm byte; font hỏng ⇒ `nil`.
    static func load(_ data: Data) -> LegadoFont? {
        guard !data.isEmpty else { return nil }
        let key = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        cacheLock.lock()
        if let cached = cache[key] {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()
        guard let made = LegadoFont(data: data) else { return nil }
        cacheLock.lock()
        cache[key] = made
        cacheOrder.append(key)
        while cacheOrder.count > 4 { cache.removeValue(forKey: cacheOrder.removeFirst()) }
        cacheLock.unlock()
        return made
    }

    func glyph(for scalar: Unicode.Scalar) -> UInt16? {
        tables.characterMap[scalar.value]
    }

    func fingerprint(of glyph: UInt16) -> String {
        lock.lock()
        if let cached = fingerprints[glyph] {
            lock.unlock()
            return cached
        }
        lock.unlock()
        let value = computeFingerprint(glyph)
        lock.lock()
        fingerprints[glyph] = value
        lock.unlock()
        return value
    }

    /// Bảng `vân tay → mã ký tự` (font chuẩn, §14.1 bước 3): trùng vân tay ⇒ ưu tiên khối CJK, rồi mã nhỏ nhất.
    func reverseIndex() -> [String: UInt32] {
        lock.lock()
        if let reverse {
            lock.unlock()
            return reverse
        }
        lock.unlock()
        var index: [String: UInt32] = [:]
        let ordered = tables.characterMap.sorted { Self.priority($0.key) < Self.priority($1.key) }
        for (code, glyph) in ordered {
            let print = fingerprint(of: glyph)
            if print != Self.emptyFingerprint, index[print] == nil { index[print] = code }
        }
        lock.lock()
        reverse = index
        lock.unlock()
        return index
    }

    private static func priority(_ code: UInt32) -> (Int, UInt32) {
        (0x4E00...0x9FFF).contains(code) ? (0, code) : (1, code)
    }

    private func computeFingerprint(_ glyph: UInt16) -> String {
        guard let path = CTFontCreatePathForGlyph(font, CGGlyph(glyph), nil), !path.isEmpty else {
            return Self.emptyFingerprint
        }
        let scale = 1000.0 / Double(tables.unitsPerEm)
        var text = ""
        path.applyWithBlock { pointer in
            let element = pointer.pointee
            let count: Int
            switch element.type {
            case .moveToPoint: text += "M"; count = 1
            case .addLineToPoint: text += "L"; count = 1
            case .addQuadCurveToPoint: text += "Q"; count = 2
            case .addCurveToPoint: text += "C"; count = 3
            case .closeSubpath: text += "Z"; count = 0
            @unknown default: count = 0
            }
            for index in 0..<count {
                let point = element.points[index]
                text += "\(Int((Double(point.x) * scale).rounded())),\(Int((Double(point.y) * scale).rounded()));"
            }
        }
        guard !text.isEmpty else { return Self.emptyFingerprint }
        return SHA256.hash(data: Data(text.utf8)).prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    /// `java.replaceFont(text, f1, f2[, filter])` (§14.1 bước 4–5): ký tự có glyph trong `obfuscated` ⇒ tra vân tay trong
    /// `standard`, thấy ⇒ thay; không thấy/không có trong `obfuscated` ⇒ giữ. `filter` (U57, cách a): bỏ ký tự mà glyph
    /// trong `obfuscated` **rỗng** (ký tự mồi vô hình), trừ khoảng trắng.
    static func replace(_ text: String, obfuscated: LegadoFont, standard: LegadoFont, filter: Bool) -> String {
        let index = standard.reverseIndex()
        var output = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            guard let glyph = obfuscated.glyph(for: scalar) else {
                output.append(scalar)
                continue
            }
            let print = obfuscated.fingerprint(of: glyph)
            if print == emptyFingerprint {
                if !filter || scalar.properties.isWhitespace { output.append(scalar) }
                continue
            }
            if let code = index[print], let mapped = Unicode.Scalar(code) {
                output.append(mapped)
            } else {
                output.append(scalar)
            }
        }
        return String(output)
    }
}
