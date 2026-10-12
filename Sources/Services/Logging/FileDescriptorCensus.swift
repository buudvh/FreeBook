import Foundation
import Darwin

/// Chẩn đoán cạn file descriptor (EMFILE) sau phiên nghe TTS dài.
///
/// Triệu chứng đã gặp trên máy thật (Google TTS, cả bộ truyện đã tải): sau vài giờ mọi lần mở file đều
/// hỏng — đọc chương `.bin`, ảnh bìa, cả bật log — báo `NSCocoaErrorDomain 256` và chỉ hết khi tắt hẳn app.
/// Đọc code chưa thấy chỗ rò, nên enum này **đếm fd đang mở theo nhóm** để log chỉ ra nhóm nào tăng dần.
///
/// - Chỉ dùng `fcntl`/`fstat`/`getsockopt`/`getpeername` trên fd sẵn có, **không mở fd mới**, nên vẫn chạy
///   được đúng lúc đã cạn.
/// - Ghi qua `AppLogger.logAlways` (không cần bật log): mỗi chương ~1 dòng, nên log đo fd không đẩy
///   các dòng khác ra khỏi vòng xoay file của `AppLogFiles`. Việc đếm chạy trên một serial queue `.utility`.
/// - `start()` còn nâng giới hạn mềm `RLIMIT_NOFILE` (thường 256) lên mức hệ thống cho phép, để người
///   dùng nghe được lâu hơn trong lúc chờ tìm chỗ rò; log vẫn thấy fd tăng dần.
enum FileDescriptorCensus {
    /// Mọi việc đếm và mọi trạng thái bên dưới chạy tuần tự trên queue này: không chặn main/TTS.
    private static let queue = DispatchQueue(label: "FreeBook.FileDescriptorCensus", qos: .utility)
    private static var previousBuckets: [String: Int] = [:]
    private static var previousTotal = 0
    private static var chunkCount = 0
    private static var failureRecorded = false
    /// Số đối tượng "có thể giữ fd" đang sống theo loại (`JSExecutor`, `WebViewLoader`…), chỉ đổi trên `queue`.
    private static var liveCounts: [String: Int] = [:]

    /// Số nhóm in ra mỗi lần đếm đủ (lần chụp lúc lỗi in tất cả).
    private static let topBucketCount = 12
    /// Số nhóm vừa tăng được in chi tiết (dải fd, cờ mở, vị trí đọc) mỗi lần đếm đủ.
    private static let detailBucketCount = 5
    /// Cứ bấy nhiêu đoạn audio thì đếm tổng một lần.
    private static let chunkSampleInterval = 100
    /// Tổng tăng quá ngưỡng này so với lần đếm đủ trước ⇒ đếm đủ ngay để bắt nhóm đang rò.
    private static let growthTriggerCount = 20
    /// Còn ít hơn ngần này fd trống thì coi như đã cạn.
    private static let nearLimitMargin = 8
    /// Không quét quá số fd này dù giới hạn mềm cao hơn.
    private static let scanCap = 16_384
    private static let raiseCandidates: [rlim_t] = [10_240, 8_192, 4_096, 2_048, 1_024]

    // MARK: - Điểm gọi

    /// Lúc khởi động: nâng giới hạn mềm (đồng bộ, trước khi app mở nhiều file) rồi ghi mốc ban đầu.
    static func start() {
        var limit = rlimit()
        guard getrlimit(RLIMIT_NOFILE, &limit) == 0 else {
            AppLogger.shared.logAlways("[FD] launch getrlimit lỗi errno=\(errno)")
            record(event: "launch")
            return
        }
        let before = limit.rlim_cur
        for candidate in raiseCandidates where candidate > limit.rlim_cur && candidate <= limit.rlim_max {
            var raised = limit
            raised.rlim_cur = candidate
            if setrlimit(RLIMIT_NOFILE, &raised) == 0 { break }
        }
        _ = getrlimit(RLIMIT_NOFILE, &limit)
        AppLogger.shared.logAlways("[FD] launch soft=\(before)->\(limit.rlim_cur) hard=\(limit.rlim_max)")
        record(event: "launch")
    }

    /// Đếm đủ theo nhóm, in tổng + chênh lệch so với lần đếm đủ trước.
    static func record(event: String) {
        queue.async { Self.recordOnQueue(event: event, includeAllBuckets: false) }
    }

    /// Mỗi đoạn audio bắt đầu phát: cứ `chunkSampleInterval` đoạn đếm tổng một lần (rẻ), tổng tăng
    /// nhanh thì đếm đủ luôn.
    static func tickChunk() {
        queue.async {
            Self.chunkCount += 1
            guard Self.chunkCount % Self.chunkSampleInterval == 0 else { return }
            let (total, soft) = Self.countOpen()
            AppLogger.shared.logAlways("[FD] chunks=\(Self.chunkCount) total=\(total)/\(soft)")
            if total - Self.previousTotal > Self.growthTriggerCount {
                Self.recordOnQueue(event: "growth", includeAllBuckets: false)
            }
        }
    }

    /// Một lần mở file vừa thất bại. Nếu do hết fd thì chụp **toàn bộ** bảng fd — mỗi phiên chạy một lần,
    /// vì đây là bằng chứng giá trị nhất. `error == nil` (API không trả lỗi, vd `UIImage(contentsOfFile:)`)
    /// thì chỉ dựa vào việc bảng fd đã sát giới hạn.
    static func noteOpenFailure(context: String, error: Error?) {
        let outOfDescriptors = error.map(isOutOfDescriptors) ?? false
        let detail = error.map(describe) ?? "-"
        queue.async {
            // Đã chụp rồi thì thôi — không quét lại bảng fd cho mỗi lần mở file hỏng sau đó.
            guard !Self.failureRecorded, outOfDescriptors || Self.isNearLimit() else { return }
            Self.failureRecorded = true
            AppLogger.shared.logAlways("[FD] FAILURE context=\(context) error=\(detail)")
            Self.recordOnQueue(event: "failure", includeAllBuckets: true)
        }
    }

    /// Số fd đang mở và giới hạn mềm — cho màn "Ghi log hệ thống". Chỉ dùng `fcntl`, gọi được từ mọi luồng.
    static func openCount() -> (open: Int, limit: Int) {
        let (total, soft) = countOpen()
        return (total, soft)
    }

    /// Đối tượng loại `kind` vừa được tạo (`+1`) hoặc giải phóng (`-1`). Gọi được từ mọi luồng, kể cả `deinit`.
    static func trackLive(_ kind: String, _ delta: Int) {
        queue.async { Self.liveCounts[kind, default: 0] += delta }
    }

    /// Lỗi có mang errno EMFILE/ENFILE ở bất kỳ tầng `NSUnderlyingError` nào.
    static func isOutOfDescriptors(_ error: Error) -> Bool {
        var current: NSError? = error as NSError
        var depth = 0
        while let nsError = current, depth < 4 {
            if nsError.domain == NSPOSIXErrorDomain, nsError.code == Int(EMFILE) || nsError.code == Int(ENFILE) {
                return true
            }
            current = nsError.userInfo[NSUnderlyingErrorKey] as? NSError
            depth += 1
        }
        return false
    }

    /// Bảng fd chỉ còn dưới `nearLimitMargin` chỗ trống.
    static func isNearLimit() -> Bool {
        let (total, soft) = countOpen()
        return total >= soft - nearLimitMargin
    }

    /// Mô tả lỗi bằng domain/code từng tầng, kèm câu mô tả đã **lưu sẵn** (`NSLocalizedDescriptionKey`,
    /// `errorDescription` của lỗi Swift). Cố ý **không** gọi `localizedDescription`: với lỗi Cocoa không có
    /// câu lưu sẵn, khi đã cạn fd CoreFoundation không nạp nổi bảng bản địa hoá và trả `couldn\U2019t…`.
    static func describe(_ error: Error) -> String {
        var parts: [String] = []
        if !(type(of: error) is NSError.Type), let text = (error as? LocalizedError)?.errorDescription {
            parts.append("\"\(text)\"")
        }
        var current: NSError? = error as NSError
        var depth = 0
        while let nsError = current, depth < 4 {
            depth += 1
            var part = "\(nsError.domain) \(nsError.code)"
            if let text = nsError.userInfo[NSLocalizedDescriptionKey] as? String {
                part += " \"\(text)\""
            }
            if let sqlite = nsError.userInfo["NSSQLiteErrorDomain"] {
                part += " sqlite=\(sqlite)"
            }
            if let path = nsError.userInfo[NSFilePathErrorKey] as? String {
                part += " file=\((path as NSString).lastPathComponent)"
            }
            parts.append(part)
            current = nsError.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return parts.joined(separator: " <- ")
    }

    // MARK: - Đếm

    /// Chỉ gọi trên `queue`.
    private static func recordOnQueue(event: String, includeAllBuckets: Bool) {
        let (total, soft, buckets, fdsByBucket) = census()
        let deltaTotal = total - previousTotal
        let ranked = buckets.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
        let shown = includeAllBuckets ? ranked : Array(ranked.prefix(topBucketCount))
        let top = shown.map { entry -> String in
            let delta = entry.value - (previousBuckets[entry.key] ?? 0)
            return delta == 0 ? "\(entry.key)=\(entry.value)" : "\(entry.key)=\(entry.value)(\(signed(delta)))"
        }
        let grownBuckets = buckets
            .map { ($0.key, $0.value - (previousBuckets[$0.key] ?? 0)) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
        let grown = grownBuckets.prefix(5).map { "\($0.0)\(signed($0.1))" }
        let live = liveCounts.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }
        AppLogger.shared.logAlways(
            "[FD] \(event) total=\(total)/\(soft) (\(signed(deltaTotal))) grow=[\(grown.joined(separator: ", "))] live=[\(live.joined(separator: ", "))] top=[\(top.joined(separator: ", "))]"
        )
        for (bucket, _) in grownBuckets.prefix(detailBucketCount) {
            AppLogger.shared.logAlways(detailLine(bucket: bucket, fds: fdsByBucket[bucket] ?? []))
        }
        previousBuckets = buckets
        previousTotal = total
    }

    private static func signed(_ value: Int) -> String {
        value >= 0 ? "+\(value)" : "\(value)"
    }

    private static func softLimit() -> Int {
        var limit = rlimit()
        guard getrlimit(RLIMIT_NOFILE, &limit) == 0 else { return 256 }
        return Int(min(limit.rlim_cur, rlim_t(scanCap)))
    }

    private static func countOpen() -> (total: Int, soft: Int) {
        let soft = softLimit()
        var total = 0
        for fd in 0..<Int32(soft) where fcntl(fd, F_GETFD) != -1 {
            total += 1
        }
        return (total, soft)
    }

    private static func census() -> (total: Int, soft: Int, buckets: [String: Int], fdsByBucket: [String: [Int32]]) {
        let soft = softLimit()
        var buckets: [String: Int] = [:]
        var fdsByBucket: [String: [Int32]] = [:]
        var total = 0
        var pathBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        for fd in 0..<Int32(soft) where fcntl(fd, F_GETFD) != -1 {
            total += 1
            let name = bucket(for: fd, pathBuffer: &pathBuffer)
            buckets[name, default: 0] += 1
            fdsByBucket[name, default: []].append(fd)
        }
        return (total, soft, buckets, fdsByBucket)
    }

    /// Chi tiết một nhóm vừa tăng: dải số fd và cờ/vị trí đọc của fd cũ nhất và mới nhất. Hai fd cùng vị trí
    /// đọc ⇒ cùng một "open file description" (bản `dup`); khác vị trí ⇒ mở độc lập. `cloexec=0` ở cả nhóm
    /// ⇒ ủng hộ giả thuyết "fd thiếu FD_CLOEXEC bị nhân bản".
    private static func detailLine(bucket: String, fds: [Int32]) -> String {
        guard let oldest = fds.min(), let newest = fds.max() else { return "[FD] detail \(bucket) n=0" }
        return "[FD] detail \(bucket) n=\(fds.count) fd=\(oldest)…\(newest) newest(\(describeFD(newest))) oldest(\(describeFD(oldest)))"
    }

    /// Cờ mở (`F_GETFL`), `FD_CLOEXEC` và vị trí đọc hiện tại — `lseek(…, 0, SEEK_CUR)` chỉ đọc, không dời vị trí.
    private static func describeFD(_ fd: Int32) -> String {
        let flags = fcntl(fd, F_GETFL)
        let descriptorFlags = fcntl(fd, F_GETFD)
        let cloexec = descriptorFlags == -1 ? "?" : ((descriptorFlags & FD_CLOEXEC) != 0 ? "1" : "0")
        let offset = lseek(fd, 0, SEEK_CUR)
        return "fd=\(fd) fl=0x\(String(UInt32(bitPattern: flags), radix: 16)) cloexec=\(cloexec) off=\(offset)"
    }

    private static func bucket(for fd: Int32, pathBuffer: inout [CChar]) -> String {
        var info = stat()
        guard fstat(fd, &info) == 0 else { return "unknown" }
        switch info.st_mode & S_IFMT {
        case S_IFREG, S_IFDIR, S_IFCHR:
            guard fcntl(fd, F_GETPATH, &pathBuffer) != -1 else { return "file(?)" }
            return normalize(String(cString: pathBuffer))
        case S_IFSOCK:
            return socketBucket(fd)
        case S_IFIFO:
            return "pipe"
        default:
            return "other(\(String(info.st_mode & S_IFMT, radix: 8)))"
        }
    }

    private static func socketBucket(_ fd: Int32) -> String {
        var socketType: Int32 = 0
        var typeLength = socklen_t(MemoryLayout<Int32>.size)
        _ = getsockopt(fd, SOL_SOCKET, SO_TYPE, &socketType, &typeLength)
        let typeName = socketType == SOCK_STREAM ? "tcp" : (socketType == SOCK_DGRAM ? "udp" : "type\(socketType)")

        var local = sockaddr_storage()
        var localLength = socklen_t(MemoryLayout<sockaddr_storage>.size)
        let localOK = withUnsafeMutablePointer(to: &local) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &localLength) == 0 }
        }
        guard localOK else { return "sock/\(typeName)" }
        let family = Int32(local.ss_family)
        if family == AF_UNIX { return "sock/unix" }
        guard family == AF_INET || family == AF_INET6 else { return "sock/af\(family)/\(typeName)" }

        var peer = sockaddr_storage()
        var peerLength = socklen_t(MemoryLayout<sockaddr_storage>.size)
        let peerOK = withUnsafeMutablePointer(to: &peer) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getpeername(fd, $0, &peerLength) == 0 }
        }
        guard peerOK else { return "sock/\(typeName)/no-peer" }
        let port: UInt16
        if Int32(peer.ss_family) == AF_INET6 {
            port = withUnsafePointer(to: &peer) {
                $0.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { UInt16(bigEndian: $0.pointee.sin6_port) }
            }
        } else {
            port = withUnsafePointer(to: &peer) {
                $0.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt16(bigEndian: $0.pointee.sin_port) }
            }
        }
        return "sock/\(typeName)/:\(port)"
    }

    private static let containerMarkers: [(marker: String, label: String)] = [
        ("/Library/Application Support/", "AS/"),
        ("/Library/Caches/", "Caches/"),
        ("/Library/", "Lib/"),
        ("/Documents/", "Docs/"),
        ("/tmp/", "tmp/"),
        (".app/", "App/"),
    ]

    private static let systemPrefixes = ["/System/", "/usr/", "/private/preboot/", "/Library/"]

    /// UUID thay trước, rồi mới tới chuỗi hex dài (SHA-256 tên file `.bin`/bìa).
    private static let nameReplacements: [(regex: NSRegularExpression?, template: String)] = [
        (regex: try? NSRegularExpression(pattern: "[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"), template: "<uuid>"),
        (regex: try? NSRegularExpression(pattern: "[0-9a-fA-F]{32,}"), template: "<hex>"),
    ]

    /// Bỏ phần đường dẫn container, thay tên băm SHA/UUID bằng `<hex>`/`<uuid>` để các file cùng loại
    /// (vd `AS/books/<hex>.bin`) gom chung một nhóm.
    private static func normalize(_ path: String) -> String {
        var result = path
        if systemPrefixes.contains(where: { path.hasPrefix($0) }) {
            result = "sys:" + (path as NSString).lastPathComponent
        } else if let match = containerMarkers.compactMap({ entry -> (label: String, range: Range<String.Index>)? in
            path.range(of: entry.marker, options: .backwards).map { (label: entry.label, range: $0) }
        }).max(by: { $0.range.upperBound < $1.range.upperBound }) {
            // Marker nằm sâu nhất thắng: `…/Documents/…/tmp/x` thành `tmp/x`, không phải `Docs/…`.
            result = match.label + String(path[match.range.upperBound...])
        }
        for replacement in nameReplacements {
            guard let regex = replacement.regex else { continue }
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: replacement.template)
        }
        return result
    }
}
