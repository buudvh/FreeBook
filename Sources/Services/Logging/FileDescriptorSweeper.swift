import Foundation
import Darwin

/// Dọn các fd "mồ côi" mà một thứ ngoài code app mở lại khi app ở nền (xem `FileDescriptorStepProbe`) — chữa
/// triệu chứng để nghe TTS lâu không cạn fd, trong lúc chưa tìm ra gốc.
///
/// Một fd chỉ bị đóng khi thoả **hết**:
/// 1. là file thường, không phải SQLite (`.db`, `.sqlite`, `-wal`, `-shm`, `-journal`) và không nằm dưới `/dev/`;
/// 2. mở chỉ-đọc, không có `FD_CLOEXEC`, vị trí đọc 0 (chưa đọc byte nào);
/// 3. cùng file (device + inode) có ít nhất `minimumPileSize` fd như vậy — một đống bản thừa;
/// 4. lần quét trước đã thấy đúng fd đó, cùng file, từ ít nhất `minimumOrphanAge` giây — loại các lần mở ngắn
///    hợp lệ (vd đọc chương từ `.bin`);
/// 5. không phải fd số nhỏ nhất của đống (luôn chừa lại một, phòng đó là bản gốc).
///
/// Chạy trên queue của `FileDescriptorCensus` (gọi từ `tickChunk`), chỉ khi tổng fd ≥ `sweepThreshold` và công tắc
/// "Tự dọn file mở thừa" (`enabledKey`, mặc định bật) đang bật. Mỗi lần dọn ghi một dòng `[FD] sweep …` — 1.3.602:
/// dòng này đã comment lại theo yêu cầu tắt log `[FD]` (việc dọn vẫn chạy như cũ).
enum FileDescriptorSweeper {
    static let enabledKey = "fdSweeperEnabled"
    /// Cứ bấy nhiêu đoạn audio thì xét dọn một lần (~1 phút với Google TTS).
    static let chunkInterval = 20
    private static let sweepThreshold = 500
    private static let minimumPileSize = 4
    private static let minimumOrphanAge: TimeInterval = 45
    private static let excludedPathMarkers = [".db", ".sqlite", "-wal", "-shm", "-journal"]

    private struct FileIdentity: Hashable {
        let device: Int32
        let inode: UInt64
    }

    private struct Sighting {
        let identity: FileIdentity
        let firstSeen: TimeInterval
    }

    /// fd ứng viên → file + lần đầu thấy. Chỉ đổi trên queue của census.
    private static var sightings: [Int32: Sighting] = [:]

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    /// Chỉ gọi trên queue của `FileDescriptorCensus`. `total`/`soft`: tổng fd vừa đếm và giới hạn quét.
    static func sweepIfNeeded(total: Int, soft: Int) {
        guard isEnabled, total >= sweepThreshold else {
            sightings.removeAll()
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        var piles: [FileIdentity: [Int32]] = [:]
        // 1.3.602: tắt log [FD] — `paths`/`closedByFile`/`closed` chỉ để dựng dòng `[FD] sweep`, bỏ comment để bật lại.
        // var paths: [FileIdentity: String] = [:]
        var pathBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        for fd in Int32(3)..<Int32(soft) where fcntl(fd, F_GETFD) != -1 {
            guard let candidate = orphanCandidate(fd, pathBuffer: &pathBuffer) else { continue }
            piles[candidate.identity, default: []].append(fd)
            // paths[candidate.identity] = candidate.path
        }

        var nextSightings: [Int32: Sighting] = [:]
        // var closedByFile: [String: Int] = [:]
        // var closed = 0
        for (identity, fds) in piles {
            let sorted = fds.sorted()
            for fd in sorted {
                let previous = sightings[fd]
                let firstSeen = previous?.identity == identity ? (previous?.firstSeen ?? now) : now
                let removable = sorted.count >= minimumPileSize && fd != sorted[0] && now - firstSeen >= minimumOrphanAge
                if removable, close(fd) == 0 {
                    // closed += 1
                    // closedByFile[FileDescriptorCensus.normalize(paths[identity] ?? "?"), default: 0] += 1
                } else {
                    nextSightings[fd] = Sighting(identity: identity, firstSeen: firstSeen)
                }
            }
        }
        sightings = nextSightings
        // guard closed > 0 else { return }
        // let top = closedByFile
        //     .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
        //     .prefix(6)
        //     .map { "\($0.key)×\($0.value)" }
        // AppLogger.shared.logAlways(
        //     "[FD] sweep total=\(total)->\(total - closed) closed=\(closed) kept=\(nextSightings.count) top=[\(top.joined(separator: ", "))]"
        // )
    }

    /// fd thoả điều kiện 1–2 thì trả file của nó, không thì `nil`. Chỉ dùng `fstat`/`fcntl`/`lseek` (không dời vị trí).
    private static func orphanCandidate(_ fd: Int32, pathBuffer: inout [CChar]) -> (identity: FileIdentity, path: String)? {
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG else { return nil }
        let flags = fcntl(fd, F_GETFL)
        let descriptorFlags = fcntl(fd, F_GETFD)
        guard flags != -1, flags & O_ACCMODE == O_RDONLY,
              descriptorFlags != -1, descriptorFlags & FD_CLOEXEC == 0,
              lseek(fd, 0, SEEK_CUR) == 0,
              fcntl(fd, F_GETPATH, &pathBuffer) != -1 else { return nil }
        let path = String(cString: pathBuffer)
        guard !path.hasPrefix("/dev/"),
              !excludedPathMarkers.contains(where: { path.contains($0) }) else { return nil }
        return (FileIdentity(device: info.st_dev, inode: info.st_ino), path)
    }
}
