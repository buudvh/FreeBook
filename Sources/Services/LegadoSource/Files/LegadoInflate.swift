import Compression
import Foundation

/// Giải nén DEFLATE cho `java.util.zip.*` giả lập của nguồn Legado (spec §6.9), trên framework `Compression`
/// (`COMPRESSION_ZLIB` = DEFLATE thô, RFC 1951) qua `compression_stream` để đầu ra không bị giới hạn trước. Ba dạng vỏ:
/// - `raw`: DEFLATE thô (`Inflater(true)`);
/// - `zlib`: header 2 byte RFC 1950 (kiểm CM = 8, CINFO ≤ 7, FCHECK; FDICT ⇒ chưa hỗ trợ), không kiểm Adler-32 cuối;
/// - `gzip`: header RFC 1952 (FEXTRA, FNAME, FCOMMENT, FHCRC), bỏ 8 byte cuối (CRC32 + ISIZE, không kiểm CRC), nối các
///   member liền nhau; byte thừa sau một member mà không phải header gzip thì bỏ qua như `GZIPInputStream`.
///
/// Chỗ dừng của mỗi member lấy từ số byte vào bộ giải còn chưa dùng khi nó báo `END`; ISIZE ở đuôi phải khớp, lệch thì
/// dừng ở member đó (chỉ mất các member sau nếu bộ giải đọc lố). Đầu ra tối đa `maxOutputBytes` = 16 MiB (chặn bom nén;
/// kết quả đi về JS dạng hex nên bộ nhớ thực tốn gấp 5–6 lần). Lỗi ⇒ `LegadoJSNativeError` (ném vào JS, nguồn
/// `try/catch` được).
enum LegadoInflate {
    enum Format: String {
        case raw
        case zlib
        case gzip
    }

    /// Dữ liệu đã giải và số byte vào đã dùng (tính cả header/đuôi của vỏ) — cho `Inflater.getRemaining()`.
    struct Outcome {
        let output: Data
        let consumed: Int
    }

    static let maxOutputBytes = 16 * 1024 * 1024
    private static let chunkSize = 64 * 1024

    static func inflate(_ data: Data, format: Format, limit: Int = LegadoInflate.maxOutputBytes) throws -> Outcome {
        let input = [UInt8](data)
        switch format {
        case .raw:
            return try inflateRaw(input, from: 0, limit: limit)
        case .zlib:
            let start = try zlibHeaderLength(input)
            let body = try inflateRaw(input, from: start, limit: limit)
            return Outcome(output: body.output, consumed: min(body.consumed + 4, input.count))
        case .gzip:
            return try inflateGzip(input, limit: limit)
        }
    }

    // MARK: - Vỏ

    /// RFC 1950: `CMF FLG`; `(CMF << 8 | FLG)` chia hết cho 31.
    private static func zlibHeaderLength(_ input: [UInt8]) throws -> Int {
        guard input.count >= 2 else { throw truncated }
        let cmf = input[0]
        let flg = input[1]
        guard cmf & 0x0F == 8, cmf >> 4 <= 7, (UInt16(cmf) << 8 | UInt16(flg)) % 31 == 0 else {
            throw LegadoJSNativeError("Giải nén: header zlib không hợp lệ (incorrect header check)")
        }
        guard flg & 0x20 == 0 else { throw LegadoJSNativeError.unsupported("zlib có từ điển đặt sẵn (FDICT)") }
        return 2
    }

    private static func inflateGzip(_ input: [UInt8], limit: Int) throws -> Outcome {
        var output = Data()
        var bodyStart = try gzipHeaderEnd(input, at: 0)
        while true {
            let member = try inflateRaw(input, from: bodyStart, limit: limit - output.count)
            output.append(member.output)
            let trailerEnd = member.consumed + 8
            guard trailerEnd <= input.count,
                  littleEndian32(input, at: member.consumed + 4) == UInt32(truncatingIfNeeded: member.output.count),
                  let next = try? gzipHeaderEnd(input, at: trailerEnd) else {
                return Outcome(output: output, consumed: min(trailerEnd, input.count))
            }
            bodyStart = next
        }
    }

    /// RFC 1952: `1f 8b 08 FLG MTIME(4) XFL OS`, rồi các trường tuỳ chọn theo `FLG`. Trả vị trí đầu dữ liệu DEFLATE.
    private static func gzipHeaderEnd(_ input: [UInt8], at offset: Int) throws -> Int {
        guard offset >= 0, input.count - offset >= 10, input[offset] == 0x1F, input[offset + 1] == 0x8B else {
            throw LegadoJSNativeError("Giải nén: không phải định dạng GZIP (Not in GZIP format)")
        }
        guard input[offset + 2] == 8 else {
            throw LegadoJSNativeError("Giải nén: GZIP dùng phương pháp nén lạ (\(input[offset + 2]))")
        }
        let flags = input[offset + 3]
        guard flags & 0xE0 == 0 else { throw LegadoJSNativeError("Giải nén: header GZIP có cờ lạ") }
        var position = offset + 10
        if flags & 0x04 != 0 {
            guard position + 2 <= input.count else { throw truncated }
            position += 2 + (Int(input[position]) | Int(input[position + 1]) << 8)
        }
        if flags & 0x08 != 0 { position = try zeroTerminatedEnd(input, from: position) }
        if flags & 0x10 != 0 { position = try zeroTerminatedEnd(input, from: position) }
        if flags & 0x02 != 0 { position += 2 }
        guard position <= input.count else { throw truncated }
        return position
    }

    private static func zeroTerminatedEnd(_ input: [UInt8], from start: Int) throws -> Int {
        var index = start
        while index < input.count {
            if input[index] == 0 { return index + 1 }
            index += 1
        }
        throw truncated
    }

    private static func littleEndian32(_ input: [UInt8], at offset: Int) -> UInt32 {
        let byte0 = UInt32(input[offset])
        let byte1 = UInt32(input[offset + 1]) << 8
        let byte2 = UInt32(input[offset + 2]) << 16
        let byte3 = UInt32(input[offset + 3]) << 24
        return byte0 | byte1 | byte2 | byte3
    }

    // MARK: - DEFLATE

    /// DEFLATE thô từ `start`; `consumed` của kết quả là vị trí (tuyệt đối trong `input`) ngay sau khối cuối.
    ///
    /// Lượt đầu không cờ để bộ giải tự báo `END` ở khối cuối (số byte còn lại khi đó là chính xác); hết đường tiến mà chưa
    /// `END` thì báo hết dữ liệu một lần (`FINALIZE`), vẫn không xong ⇒ dữ liệu cụt. `ERROR` ở lượt đầu ⇒ dữ liệu hỏng.
    private static func inflateRaw(_ input: [UInt8], from start: Int, limit: Int) throws -> Outcome {
        let available = input.count - start
        guard start >= 0, available > 0 else { throw truncated }
        let stream = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
        defer { stream.deallocate() }
        guard compression_stream_init(stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK else {
            throw LegadoJSNativeError("Giải nén: không khởi tạo được bộ giải DEFLATE")
        }
        defer { _ = compression_stream_destroy(stream) }
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: chunkSize)
        defer { buffer.deallocate() }
        return try input.withUnsafeBufferPointer { whole -> Outcome in
            guard let base = whole.baseAddress else { throw truncated }
            var output = Data()
            stream.pointee.src_ptr = base + start
            stream.pointee.src_size = available
            var flags: Int32 = 0
            while true {
                let pending = stream.pointee.src_size
                stream.pointee.dst_ptr = buffer
                stream.pointee.dst_size = chunkSize
                let status = compression_stream_process(stream, flags)
                let produced = chunkSize - stream.pointee.dst_size
                if produced > 0 {
                    guard output.count + produced <= limit else {
                        throw LegadoJSNativeError("Giải nén: dữ liệu sau giải nén vượt \(maxOutputBytes / 1024 / 1024) MiB")
                    }
                    output.append(buffer, count: produced)
                }
                switch status {
                case COMPRESSION_STATUS_END:
                    return Outcome(output: output, consumed: start + available - stream.pointee.src_size)
                case COMPRESSION_STATUS_OK:
                    guard produced == 0, stream.pointee.src_size == pending else { continue }
                    guard flags == 0 else { throw truncated }
                    flags = Int32(COMPRESSION_STREAM_FINALIZE.rawValue)
                default:
                    throw flags == 0 ? LegadoJSNativeError("Giải nén: dữ liệu nén hỏng") : truncated
                }
            }
        }
    }

    private static var truncated: LegadoJSNativeError {
        LegadoJSNativeError("Giải nén: dữ liệu nén bị cụt (Unexpected end of ZLIB input stream)")
    }
}
