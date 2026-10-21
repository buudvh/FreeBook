import Foundation

/// Bộ đọc DER tối thiểu để bóc lớp bọc khoá RSA (spec §14.3): X.509 `SubjectPublicKeyInfo` → PKCS#1 `RSAPublicKey`,
/// PKCS#8 `PrivateKeyInfo` → PKCS#1 `RSAPrivateKey` (Security.framework chỉ nhận PKCS#1).
enum LegadoDER {
    struct Element {
        let tag: UInt8
        /// Vị trí nội dung (không gồm tag + độ dài) trong mảng gốc.
        let content: Range<Int>
        /// Vị trí ngay sau phần tử.
        let end: Int
    }

    static let sequence: UInt8 = 0x30
    static let integer: UInt8 = 0x02
    static let bitString: UInt8 = 0x03
    static let octetString: UInt8 = 0x04

    /// Đọc một phần tử bắt đầu tại `offset`; `nil` khi hỏng/vượt biên.
    static func element(in bytes: [UInt8], at offset: Int) -> Element? {
        guard offset + 2 <= bytes.count else { return nil }
        let tag = bytes[offset]
        var index = offset + 1
        var length = Int(bytes[index])
        index += 1
        if length & 0x80 != 0 {
            let count = length & 0x7F
            guard count > 0, count <= 4, index + count <= bytes.count else { return nil }
            length = 0
            for _ in 0..<count {
                length = (length << 8) | Int(bytes[index])
                index += 1
            }
        }
        guard length >= 0, index + length <= bytes.count else { return nil }
        return Element(tag: tag, content: index..<(index + length), end: index + length)
    }

    /// Các phần tử con trực tiếp của một SEQUENCE.
    static func children(of parent: Element, in bytes: [UInt8]) -> [Element] {
        var output: [Element] = []
        var offset = parent.content.lowerBound
        while offset < parent.content.upperBound, let child = element(in: bytes, at: offset) {
            output.append(child)
            offset = child.end
        }
        return output
    }

    /// Khoá công khai → PKCS#1 `RSAPublicKey` (bóc `SubjectPublicKeyInfo` nếu có).
    static func pkcs1PublicKey(_ data: Data) -> Data {
        let bytes = [UInt8](data)
        guard let outer = element(in: bytes, at: 0), outer.tag == sequence else { return data }
        let parts = children(of: outer, in: bytes)
        // SubjectPublicKeyInfo = SEQUENCE { AlgorithmIdentifier (SEQUENCE), BIT STRING }.
        if parts.count >= 2, parts[0].tag == sequence, parts[1].tag == bitString, parts[1].content.count > 1 {
            let start = parts[1].content.lowerBound + 1
            return Data(bytes[start..<parts[1].content.upperBound])
        }
        return data
    }

    /// Khoá riêng → PKCS#1 `RSAPrivateKey` (bóc PKCS#8 `PrivateKeyInfo` nếu có).
    static func pkcs1PrivateKey(_ data: Data) -> Data {
        let bytes = [UInt8](data)
        guard let outer = element(in: bytes, at: 0), outer.tag == sequence else { return data }
        let parts = children(of: outer, in: bytes)
        // PrivateKeyInfo = SEQUENCE { INTEGER version, AlgorithmIdentifier (SEQUENCE), OCTET STRING }.
        if parts.count >= 3, parts[0].tag == integer, parts[1].tag == sequence, parts[2].tag == octetString {
            return Data(bytes[parts[2].content])
        }
        return data
    }
}
