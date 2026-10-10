import Foundation

/// Bộ bóc frame của phản hồi `rt=c`: sau tiền tố chống XSSI `)]}'` là chuỗi các frame
/// `<độ dài>\n<JSON>` với **độ dài tính theo đơn vị UTF-16** (độ dài chuỗi JavaScript), không phải
/// byte hay ký tự. Buffer giữ dạng `[UInt16]` nên cắt frame là cắt mảng, không phải đếm lại.
///
/// Port của `StreamingFrameParser` trong `gemini-webapi`, tăng dần: `feed` trả về các frame đã trọn
/// vẹn, phần dở dang nằm lại chờ chunk sau. Mỗi frame JSON là một mảng envelope; các phần tử được
/// trải phẳng vào kết quả để bên gọi duyệt từng envelope.
struct GeminiWebFrameParser {
    private var buffer: [UInt16] = []
    private var prefixChecked = false
    private var expectedUnits: Int?
    private var payloadStart = 0

    private static let prefix: [UInt16] = Array(")]}'".utf16)

    init() {}

    mutating func feed(_ chunk: String) -> [Any] {
        buffer.append(contentsOf: chunk.utf16)
        stripPrefixOnce()

        var frames: [Any] = []
        while true {
            if expectedUnits == nil, !readLengthMarker() { break }
            guard let expected = expectedUnits else { break }
            let end = payloadStart + expected
            guard buffer.count >= end else { break }

            let payload = String(decoding: buffer[payloadStart..<end], as: UTF16.self)
            buffer.removeFirst(end)
            expectedUnits = nil
            payloadStart = 0

            let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  let data = trimmed.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
                continue
            }
            if let array = json as? [Any] {
                frames.append(contentsOf: array)
            } else {
                frames.append(json)
            }
        }
        return frames
    }

    /// Bóc nốt frame đã đủ dữ liệu sau khi stream kết thúc.
    mutating func flush() -> [Any] {
        feed("")
    }

    // MARK: - Nội bộ

    /// Bỏ `)]}'` đúng một lần; chưa đủ 4 đơn vị mà vẫn khớp đầu tiền tố thì chờ chunk sau.
    private mutating func stripPrefixOnce() {
        guard !prefixChecked else { return }
        let prefix = Self.prefix
        if buffer.count < prefix.count {
            if buffer.elementsEqual(prefix.prefix(buffer.count)) { return }
        }
        if buffer.starts(with: prefix) {
            buffer.removeFirst(prefix.count)
            trimLeadingWhitespace()
        }
        prefixChecked = true
    }

    private mutating func trimLeadingWhitespace() {
        var index = 0
        while index < buffer.count, Self.isWhitespace(buffer[index]) { index += 1 }
        if index > 0 { buffer.removeFirst(index) }
    }

    private static func isWhitespace(_ unit: UInt16) -> Bool {
        unit == 0x20 || unit == 0x0A || unit == 0x0D || unit == 0x09
    }

    /// Marker `(\d+)\n` ở đầu buffer; payload bắt đầu **ngay sau chữ số** (ký tự xuống dòng tính vào độ dài).
    /// Trả `false` khi chưa đủ dữ liệu để biết sau dãy số là gì.
    private mutating func readLengthMarker() -> Bool {
        trimLeadingWhitespace()
        guard !buffer.isEmpty else { return false }

        var index = 0
        var value = 0
        while index < buffer.count, buffer[index] >= 0x30, buffer[index] <= 0x39 {
            value = value * 10 + Int(buffer[index] - 0x30)
            index += 1
            if index > 12 { return false }
        }
        guard index > 0, index < buffer.count else { return false }
        guard buffer[index] == 0x0A else { return false }

        expectedUnits = value
        payloadStart = index
        return true
    }
}
