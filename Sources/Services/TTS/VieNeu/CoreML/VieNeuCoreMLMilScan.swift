import Foundation

/// Đọc lướt `model.mil` (chương trình Core ML dạng chữ) của bản biên dịch, giữ vài **dòng dài nhất** kèm phần đầu dòng
/// (tên + kiểu của hằng) — cho phép đo P2b-0. Báo cáo §13: trọng số Linear nằm thẳng trong chương trình (hằng
/// immediate do Core ML EP chuyển vị B của `Gemm` sinh ra), mỗi hằng là một dòng dài cả MB; tên kết thúc `_t` là dấu
/// hiệu của đường đó.
///
/// Đọc từng khối 4 MB, tìm xuống dòng bằng `memchr` — không giữ cả file (VE ~550 MB) trong RAM.
enum VieNeuCoreMLMilScan {
    struct Line: Sendable {
        let length: Int
        let prefix: String
    }

    struct Result: Sendable {
        let lines: [Line]
        let totalBytes: Int
        let lineCount: Int
    }

    static func longestLines(_ url: URL, count: Int = 5, prefixBytes: Int = 160) throws -> Result {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var top: [Line] = []
        var currentLength = 0
        var currentPrefix: [UInt8] = []
        var totalBytes = 0
        var lineCount = 0

        func finishLine() {
            lineCount += 1
            if top.count < count || currentLength > (top.last?.length ?? 0) {
                top.append(Line(length: currentLength, prefix: String(decoding: currentPrefix, as: UTF8.self)))
                top.sort { $0.length > $1.length }
                if top.count > count { top.removeLast() }
            }
            currentLength = 0
            currentPrefix.removeAll(keepingCapacity: true)
        }

        while true {
            try Task.checkCancellation()
            let chunk: Data? = try autoreleasepool { try handle.read(upToCount: 4 << 20) }
            guard let chunk, !chunk.isEmpty else { break }
            totalBytes += chunk.count
            chunk.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
                guard let base = raw.baseAddress else { return }
                var offset = 0
                while offset < raw.count {
                    let start = base + offset
                    let remaining = raw.count - offset
                    let newline = memchr(start, 0x0A, remaining).map { UnsafeRawPointer($0) }
                    let segment = newline.map { start.distance(to: $0) } ?? remaining
                    if currentPrefix.count < prefixBytes {
                        let take = min(prefixBytes - currentPrefix.count, segment)
                        let bytes = UnsafeRawBufferPointer(start: start, count: take)
                        currentPrefix.append(contentsOf: bytes)
                    }
                    currentLength += segment
                    if newline != nil {
                        finishLine()
                        offset += segment + 1
                    } else {
                        offset = raw.count
                    }
                }
            }
        }
        if currentLength > 0 { finishLine() }
        return Result(lines: top, totalBytes: totalBytes, lineCount: lineCount)
    }
}
