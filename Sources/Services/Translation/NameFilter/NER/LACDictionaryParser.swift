import Foundation

/// Đọc file từ điển văn bản của LAC đúng như Python của LAC đọc, trên **Unicode scalar**.
///
/// Dòng tách ở `\n`; đoạn rỗng sau `\n` cuối file không phải một dòng (cách Python lặp file). Python mở file ở chế độ
/// universal newline nên `\r` cũng là xuống dòng — bốn file từ điển của bản ghim không có `\r` nào (đã đếm khi xuất), và
/// lúc nạp đã kiểm sha256, nên ở đây không xử lý `\r`.
enum LACDictionaryParser {
    static let tab: UInt32 = 0x09
    static let space: UInt32 = 0x20

    /// Gọi `body` cho từng dòng (không gồm `\n`). Dữ liệu không phải UTF-8 hợp lệ ⇒ `invalidFiles`.
    static func forEachLine(
        _ data: Data,
        file name: String,
        _ body: (ArraySlice<UInt32>) throws -> Void
    ) throws {
        guard let text = String(data: data, encoding: .utf8) else {
            throw LACModelError.invalidFiles("\(name) không phải UTF-8")
        }
        var line: [UInt32] = []
        line.reserveCapacity(64)
        for scalar in text.unicodeScalars {
            if scalar.value == 0x0A {
                try body(line[...])
                line.removeAll(keepingCapacity: true)
            } else {
                line.append(scalar.value)
            }
        }
        if !line.isEmpty { try body(line[...]) }
    }

    /// `line.split(sep)` của Python khi kết quả có **đúng hai** phần (giữ phần rỗng), ngược lại `nil`.
    static func splitPair(_ line: ArraySlice<UInt32>, separator: UInt32) -> (ArraySlice<UInt32>, ArraySlice<UInt32>)? {
        guard let index = line.firstIndex(of: separator) else { return nil }
        let rest = line[(index + 1)...]
        guard !rest.contains(separator) else { return nil }
        return (line[line.startIndex..<index], rest)
    }

    /// Bỏ khoảng trắng ASCII hai đầu (`str.strip()` của Python bỏ cả khoảng trắng Unicode, nhưng `small_seg.dic` của bản
    /// ghim không có dòng nào có khoảng trắng thừa — đã đếm khi xuất).
    static func trimmed(_ line: ArraySlice<UInt32>) -> ArraySlice<UInt32> {
        func isSpace(_ value: UInt32) -> Bool { value == 0x20 || (0x09...0x0D).contains(value) }
        var start = line.startIndex
        var end = line.endIndex
        while start < end, isSpace(line[start]) { start += 1 }
        while end > start, isSpace(line[end - 1]) { end -= 1 }
        return line[start..<end]
    }

    /// Số nguyên không âm chỉ gồm chữ số ASCII, `nil` khi khác (Python `int()` sẽ văng ⇒ coi file hỏng).
    static func integer(_ digits: ArraySlice<UInt32>) -> Int? {
        guard !digits.isEmpty, digits.count <= 18 else { return nil }
        var value = 0
        for digit in digits {
            guard (0x30...0x39).contains(digit) else { return nil }
            value = value * 10 + Int(digit - 0x30)
        }
        return value
    }

    /// Chuỗi từ dãy scalar (dãy luôn từ một `String` hợp lệ nên scalar nào cũng hợp lệ).
    static func string<C: Collection>(_ scalars: C) -> String where C.Element == UInt32 {
        var view = String.UnicodeScalarView()
        for value in scalars {
            if let scalar = Unicode.Scalar(value) { view.append(scalar) }
        }
        return String(view)
    }
}
