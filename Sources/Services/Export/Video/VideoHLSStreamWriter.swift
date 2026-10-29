import Foundation

/// Nối các đoạn của một `VideoHLSLocalStream` thành **một file** theo đúng thứ tự playlist: init fMP4 (ghi lại mỗi khi
/// đổi) rồi từng đoạn, giải mã AES-128-CBC từng đoạn khi có khoá (`VideoAES128CBCDecryptor`).
///
/// - Đọc theo khúc `chunkSize` qua `FileHandle`, ghi qua `ExportStagingFile` (`.part` → đổi tên khi xong) — không bao giờ
///   giữ cả tập (hay cả một đoạn lớn) trong RAM; mỗi khúc trong `autoreleasepool` vì một tập có thể có hàng nghìn đoạn.
/// - Huỷ: `Task.checkCancellation()` trước mỗi đoạn (tác vụ xuất chạy trong `Task.detached` của `DownloadManager`).
/// - Không chuyển container: đoạn `.ts` ra file `.ts`, fMP4 ra init + đoạn nối liền (`.mp4`/`.m4a`).
enum VideoHLSStreamWriter {
    static let chunkSize = 1 << 20

    /// Kiểu hộp MP4 thường gặp ở đầu init chưa mã hoá — gặp thì chép thẳng dù playlist có khoá trước `EXT-X-MAP`.
    private static let plainInitBoxTypes: Set<String> = ["ftyp", "styp", "moov", "sidx", "free", "skip", "moof"]

    /// `onSourceBytes(số byte nguồn đã đọc)` sau mỗi đoạn — caller tự gom nhịp báo tiến độ.
    @discardableResult
    static func write(_ stream: VideoHLSLocalStream, to target: URL, onSourceBytes: (Int64) -> Void) throws -> URL {
        let staging = try ExportStagingFile(targetURL: target)
        do {
            var writtenInit: VideoHLSLocalStream.Part?
            var sourceRead: Int64 = 0
            for segment in stream.segments {
                try Task.checkCancellation()
                if let initPart = segment.initPart, initPart != writtenInit {
                    sourceRead += try append(initPart, isInit: true, to: staging)
                    writtenInit = initPart
                }
                sourceRead += try append(segment.part, isInit: false, to: staging)
                onSourceBytes(sourceRead)
            }
            guard staging.bytesWritten > 0 else { throw VideoHLSLocalStream.StreamError.empty }
            return try staging.commit()
        } catch {
            staging.discard()
            throw error
        }
    }

    /// Chép (và giải mã nếu có khoá) một vùng byte vào file đích. Trả số byte nguồn đã đọc.
    private static func append(_ part: VideoHLSLocalStream.Part, isInit: Bool, to staging: ExportStagingFile) throws -> Int64 {
        let handle = try FileHandle(forReadingFrom: part.file)
        defer { try? handle.close() }
        let start = UInt64(max(0, part.byteRange?.offset ?? 0))
        try handle.seek(toOffset: start)

        var decryptor: VideoAES128CBCDecryptor?
        if let key = part.key, let iv = part.iv {
            if isInit, try isPlainMP4Box(handle) {
                try handle.seek(toOffset: start)
            } else {
                try handle.seek(toOffset: start)
                decryptor = try VideoAES128CBCDecryptor(key: key, iv: iv)
            }
        }

        var remaining = part.byteRange?.length
        var total: Int64 = 0
        while remaining.map({ $0 > 0 }) ?? true {
            let want = remaining.map { Int(min(Int64(chunkSize), $0)) } ?? chunkSize
            let reachedEnd: Bool = try autoreleasepool {
                guard let chunk = try handle.read(upToCount: want), !chunk.isEmpty else { return true }
                total += Int64(chunk.count)
                remaining = remaining.map { $0 - Int64(chunk.count) }
                try staging.write(try decryptor?.update(chunk) ?? chunk)
                return false
            }
            if reachedEnd { break }
        }
        if let expected = part.byteRange?.length, total < expected {
            throw VideoHLSLocalStream.StreamError.truncated(part.displayName)
        }
        if let decryptor {
            try staging.write(try decryptor.finish())
        }
        return total
    }

    /// 8 byte đầu là header hộp MP4 (`size` + kiểu ASCII quen thuộc) ⇒ init không bị mã hoá.
    private static func isPlainMP4Box(_ handle: FileHandle) throws -> Bool {
        guard let head = try handle.read(upToCount: 8), head.count == 8 else { return false }
        let type = String(decoding: head.suffix(4), as: UTF8.self)
        return plainInitBoxTypes.contains(type)
    }
}
