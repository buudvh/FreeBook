import Foundation
import UIKit

/// Nhật ký của app. Từ 1.3.948 lưu bằng **SQLite theo phiên** (`AppLogDatabase`, `app_logs.sqlite`): mỗi lần mở app là một
/// phiên kèm thông tin đầu phiên (`AppLogSessionInfo`), giữ 20 phiên / tối đa 30 MB, xuất `.txt` theo phiên đã chọn
/// (`AppLogger+Sessions`). File `app_logs*.txt` xoay vòng cũ bị xoá ở lần mở đầu tiên.
///
/// - Công tắc "Ghi log hệ thống" **tự tắt mỗi lần mở app** (giữ như cũ, anh Bửu chọn); tắt thì vẫn ghi dòng lỗi (chứa ❌).
/// - Ghi theo **lô** trên hàng đợi nền: đủ 64 dòng hoặc sau 0,5 s; dòng ❌ ghi ngay (app chết vẫn còn manh mối).
/// - App vào nền / bị đóng ⇒ ghi nốt **đồng bộ** rồi đánh dấu trạng thái phiên; phiên cũ còn `foreground` lúc mở app sau
///   ⇒ nó chết khi đang mở (crash, bị giết) — phiên mới ghi lại thời điểm + dòng cuối của nó.
public final class AppLogger {
    public static let shared = AppLogger()

    public var isLoggingEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: "isLoggingEnabled") == nil {
                return false
            }
            return UserDefaults.standard.bool(forKey: "isLoggingEnabled")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "isLoggingEnabled")
        }
    }

    public var isCompactSuccessLogEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: "isCompactSuccessLogEnabled") == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: "isCompactSuccessLogEnabled")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "isCompactSuccessLogEnabled")
        }
    }

    public var isTTSVerboseLoggingEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: "isTTSVerboseLoggingEnabled") == nil {
                return false
            }
            return UserDefaults.standard.bool(forKey: "isTTSVerboseLoggingEnabled")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "isTTSVerboseLoggingEnabled")
        }
    }

    static let keptSessions = 20
    static let maxDatabaseBytes: Int64 = 30 * 1024 * 1024
    private static let batchSize = 64
    private static let flushDelay: TimeInterval = 0.5
    private static let pruneEveryLines = 2_000
    /// Kho chưa mở được (vd cạn fd) ⇒ giữ tối đa chừng này dòng chờ lần mở sau, và chỉ thử mở lại sau chừng này giây.
    private static let maxPendingWithoutStore = 2_000
    private static let reopenInterval: TimeInterval = 30

    // Một formatter dùng chung (in console + xuất `.txt`); chỉ dùng trên `queue` hoặc trong lượt xuất.
    static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()

    private static let clockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss dd/MM"
        return formatter
    }()

    /// Mọi thao tác trên kho log chạy tuần tự trên queue nền này: luồng gọi (kể cả main) chỉ dựng chuỗi rồi đi tiếp.
    let queue = DispatchQueue(label: "TangCongCac.AppLogger", qos: .utility)
    // Các biến dưới chỉ truy cập trên `queue`.
    var database: AppLogDatabase?
    var sessionId: Int64?
    private var pending: [AppLogDatabase.Line] = []
    private var flushScheduled = false
    private var linesSincePrune = 0
    private var lastOpenAttempt: TimeInterval = -.greatestFiniteMagnitude
    private var observers: [NSObjectProtocol] = []

    private init() {
        // Tự động tắt ghi log hệ thống khi khởi chạy lại ứng dụng (giữ từ 15/07 — bản sửa crash).
        UserDefaults.standard.set(false, forKey: "isLoggingEnabled")
        observeAppState()
        // Mở phiên ngay (không chờ dòng đầu) để lần mở app nào cũng có phiên + thông tin đầu phiên.
        queue.async { self.ensureSessionOnQueue() }
    }

    // Công tắc log tắt thì vẫn ghi **dòng lỗi** (chứa "❌") để lỗi xảy ra lúc chưa bật log còn dấu vết;
    // muốn một dòng luôn được ghi thì đánh dấu ❌. Vì vậy chuỗi luôn được dựng ra mới biết có phải dòng lỗi.
    public func log(_ message: @autoclosure () -> String) {
        let text = message()
        guard isLoggingEnabled || text.contains("❌") else { return }
        enqueue(text, at: Date())
    }

    /// Ghi một dòng **bất kể công tắc log** — chỉ dành cho `FileDescriptorCensus` (~1 dòng mỗi chương).
    public func logAlways(_ message: String) {
        enqueue(message, at: Date())
    }

    public func logTTSVerbose(_ message: @autoclosure () -> String) {
        guard isLoggingEnabled && isTTSVerboseLoggingEnabled else { return }
        log(message())
    }

    /// Thời điểm lấy ở luồng gọi; in console và gom lô làm trên `queue`.
    private func enqueue(_ text: String, at date: Date) {
        queue.async {
            print("[\(Self.timestampFormatter.string(from: date))] \(text)")
            let line = AppLogDatabase.Line(ts: date, isError: text.contains("❌"), text: text)
            self.pending.append(line)
            if line.isError || self.pending.count >= Self.batchSize {
                self.flushOnQueue()
            } else if !self.flushScheduled {
                self.flushScheduled = true
                self.queue.asyncAfter(deadline: .now() + Self.flushDelay) {
                    self.flushScheduled = false
                    self.flushOnQueue()
                }
            }
        }
    }

    /// Ghi các dòng đang chờ thành một lô. **Chỉ gọi trên `queue`.**
    func flushOnQueue() {
        guard !pending.isEmpty else { return }
        ensureSessionOnQueue()
        guard let database, let sessionId else {
            if pending.count > Self.maxPendingWithoutStore {
                pending.removeFirst(pending.count - Self.maxPendingWithoutStore)
            }
            return
        }
        let batch = pending
        pending.removeAll(keepingCapacity: true)
        database.append(batch, sessionId: sessionId)
        linesSincePrune += batch.count
        if linesSincePrune >= Self.pruneEveryLines {
            linesSincePrune = 0
            database.prune(keep: Self.keptSessions, maxBytes: Self.maxDatabaseBytes, current: sessionId)
        }
    }

    /// Mở kho (một lần) và phiên của lần mở app này. **Chỉ gọi trên `queue`.**
    func ensureSessionOnQueue() {
        guard sessionId == nil else { return }
        if database == nil {
            let now = ProcessInfo.processInfo.systemUptime
            guard now - lastOpenAttempt >= Self.reopenInterval else { return }
            lastOpenAttempt = now
            Self.removeLegacyTextLogs()
            database = AppLogDatabase()
        }
        guard let database else { return }
        let prevEnd = Self.describePreviousEnd(database.sessions().first, database: database)
        sessionId = database.beginSession(AppLogSessionInfo.capture(), prevEnd: prevEnd)
        database.prune(keep: Self.keptSessions, maxBytes: Self.maxDatabaseBytes, current: sessionId)
    }

    /// Xoá **tất cả** phiên rồi mở phiên mới (Màn Ghi log, màn Dung lượng, lịch tự dọn log).
    public func clear() {
        queue.sync {
            pending.removeAll()
            database?.deleteAll()
            sessionId = nil
            ensureSessionOnQueue()
        }
    }

    /// Sắp tự kết thúc tiến trình (LiveContainer chuyển app tự `SIGKILL`) ⇒ ghi nốt + đánh dấu phiên đã đóng, để lần mở sau
    /// không báo nhầm "chết đột ngột".
    public func markSessionEnded() {
        updateState("ended", synchronously: true)
    }

    // MARK: - Trạng thái app

    private func observeAppState() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: nil) { [weak self] _ in
            self?.updateState("background", synchronously: true)
        })
        observers.append(center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: nil) { [weak self] _ in
            self?.updateState("foreground", synchronously: false)
        })
        observers.append(center.addObserver(forName: UIApplication.willTerminateNotification, object: nil, queue: nil) { [weak self] _ in
            self?.updateState("ended", synchronously: true)
        })
    }

    /// Ghi nốt các dòng chờ rồi đổi trạng thái phiên. Vào nền / đóng app ⇒ **đồng bộ**: xong trước khi app bị treo, không
    /// transaction nào còn mở.
    private func updateState(_ state: String, synchronously: Bool) {
        let work = {
            self.flushOnQueue()
            if let database = self.database, let sessionId = self.sessionId {
                database.setState(state, sessionId: sessionId)
            }
        }
        if synchronously {
            queue.sync(execute: work)
        } else {
            queue.async(execute: work)
        }
    }

    // MARK: - Đầu phiên

    private static func describePreviousEnd(_ previous: AppLogDatabase.SessionRow?, database: AppLogDatabase) -> String {
        guard let previous else { return "" }
        let time = clockFormatter.string(from: previous.lastSeen)
        switch previous.state {
        case "foreground":
            let last = database.lastLine(sessionId: previous.id)?.text ?? "—"
            return "chết đột ngột lúc \(time) khi đang mở app — dòng cuối: \(String(last.prefix(300)))"
        case "background":
            return "kết thúc ở nền (lần cuối \(time))"
        default:
            return "đóng bình thường lúc \(time)"
        }
    }

    /// File log chữ của bản trước 1.3.948 (`app_logs.txt`, `app_logs.1…4.txt`) — anh Bửu chọn xoá ngay khi cập nhật.
    private static func removeLegacyTextLogs() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        for name in ["app_logs.txt"] + (1...4).map({ "app_logs.\($0).txt" }) {
            let url = directory.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: url.path) {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }
}

// MARK: - AppDiagnostics
public final class AppDiagnostics: ObservableObject {
    public static let shared = AppDiagnostics()

    @Published public var lastCall: CallInfo? = nil

    private init() {}

    public struct CallInfo: Identifiable {
        public let id = UUID()
        public let timestamp = Date()
        public let action: String
        public let input: String
        public let status: String
        public let details: String
    }
}
