import Foundation

/// Danh sách phiên, xuất `.txt` và xoá phiên cho màn "Ghi log hệ thống" (1.3.948). Kết quả trả trên main.
extension AppLogger {
    public struct SessionSummary: Identifiable, Sendable {
        public let id: Int64
        public let startedAt: Date
        /// "1.3.948 (1279)".
        public let versionDisplay: String
        public let lineCount: Int
        public let errorCount: Int
        /// Phiên của lần mở app này (đang ghi) — không xoá được.
        public let isCurrent: Bool
        /// Phiên cũ kết thúc khi app đang mở (crash, bị giết) — trạng thái cuối còn `foreground`.
        public let diedAbruptly: Bool
    }

    /// Các phiên (mới nhất trước) + dung lượng kho. Ghi nốt dòng đang chờ trước để số dòng đúng.
    public func loadSessions(completion: @escaping ([SessionSummary], Int64) -> Void) {
        queue.async {
            self.flushOnQueue()
            let current = self.sessionId
            let rows = self.database?.sessions() ?? []
            let bytes = self.database?.usedBytes ?? 0
            let summaries = rows.map { row in
                SessionSummary(
                    id: row.id,
                    startedAt: row.startedAt,
                    versionDisplay: AppLogSessionInfo.versionDisplay(version: row.version, build: row.build),
                    lineCount: row.lineCount,
                    errorCount: row.errorCount,
                    isCurrent: row.id == current,
                    diedAbruptly: row.id != current && row.state == "foreground"
                )
            }
            DispatchQueue.main.async { completion(summaries, bytes) }
        }
    }

    /// Xoá các phiên đã chọn (bỏ qua phiên đang ghi).
    public func deleteSessions(_ ids: [Int64], completion: @escaping () -> Void) {
        queue.async {
            let current = self.sessionId
            self.database?.delete(sessionIds: ids.filter { $0 != current })
            DispatchQueue.main.async { completion() }
        }
    }

    /// Ghi các phiên đã chọn (cũ → mới) vào **một** file `.txt` ở `Caches/log-exports/` (lần xuất sau xoá file cũ). Đọc qua
    /// một kết nối riêng ngoài `queue` (WAL đọc song song được) ⇒ xuất 30 MB không chặn việc ghi log hay lúc app vào nền.
    public func exportSessions(_ ids: [Int64], completion: @escaping (URL?) -> Void) {
        queue.async {
            self.flushOnQueue()
            DispatchQueue.global(qos: .userInitiated).async {
                let url = Self.writeExport(sessionIds: ids)
                DispatchQueue.main.async { completion(url) }
            }
        }
    }

    // MARK: - Ghi file xuất

    private static let exportPageSize = 2_000

    private static func writeExport(sessionIds: [Int64]) -> URL? {
        guard let reader = AppLogDatabase() else { return nil }
        let wanted = Set(sessionIds)
        let rows = reader.sessions().filter { wanted.contains($0.id) }.sorted { $0.id < $1.id }
        guard !rows.isEmpty else { return nil }

        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("log-exports", isDirectory: true)
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stamp = DateFormatter()
        stamp.dateFormat = "yyyyMMdd-HHmm"
        let build = AppVersionInfo.buildNumber ?? "0"
        let url = directory.appendingPathComponent("TangCongCac-log-\(build)-\(stamp.string(from: Date())).txt")
        guard FileManager.default.createFile(atPath: url.path, contents: nil),
              let handle = try? FileHandle(forWritingTo: url) else { return nil }
        defer { try? handle.close() }

        for (position, row) in rows.enumerated() {
            let separator = position == 0 ? "" : "\n"
            write(separator + header(for: row), to: handle)
            var afterId: Int64?
            while true {
                let page = reader.lines(sessionId: row.id, afterId: afterId, limit: exportPageSize)
                guard let last = page.last else { break }
                afterId = last.id
                var chunk = ""
                chunk.reserveCapacity(page.count * 120)
                for item in page {
                    chunk += "[\(timestampFormatter.string(from: item.line.ts))] \(item.line.text)\n"
                }
                write(chunk, to: handle)
                if page.count < exportPageSize { break }
            }
        }
        return url
    }

    private static func write(_ text: String, to handle: FileHandle) {
        try? handle.write(contentsOf: Data(text.utf8))
    }

    /// Khối đầu mỗi phiên trong file xuất.
    private static func header(for row: AppLogDatabase.SessionRow) -> String {
        let started = DateFormatter()
        started.dateFormat = "HH:mm:ss dd/MM/yyyy"
        let state: String
        switch row.state {
        case "foreground": state = "đang mở (phiên đang ghi, hoặc đã chết đột ngột)"
        case "background": state = "ở nền"
        default: state = "đã đóng"
        }
        var lines = [
            "===== Phiên \(started.string(from: row.startedAt)) =====",
            "App \(AppLogSessionInfo.versionDisplay(version: row.version, build: row.build)) · \(row.device) · \(row.os)",
            "Nhiệt: \(row.thermal) · RAM trống \(row.ramFreeMB) MB · Ổ trống \(row.diskFreeMB) MB",
            "TTS: \(row.tts)"
        ]
        if !row.prevEnd.isEmpty { lines.append("Phiên trước: \(row.prevEnd)") }
        lines.append("Trạng thái cuối: \(state) · \(row.lineCount) dòng · \(row.errorCount) lỗi")
        return lines.joined(separator: "\n") + "\n"
    }
}
