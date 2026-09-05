import Foundation

/// Envelope và payload của giao thức `freebook-extdebug.v1`.
///
/// Một kiểu duy nhất cho cả hai chiều: client gửi `Envelope` có `type` là lệnh, server trả `Envelope`
/// có `type` là `reply`/`error`/`event`. `requestId` do client sinh và server echo lại; event do server
/// tự phát có `requestId` là subscription id.
///
/// Mọi trường đều là `String`/`Int`/`Bool` hoặc kiểu Codable đã khai ở đây — **không** có `[String: Any]`,
/// vì payload động là chỗ dễ nhất để một field chưa redact lọt qua.
public enum ExtensionDebugProtocol {
    public static let subprotocol = "freebook-extdebug.v1"
    public static let version = 1
    /// Trần một message; lớn hơn thì đóng kết nối. Client chỉ gửi lệnh nhỏ, trừ chunk source ở Phase 3.
    public static let maxIncomingMessageBytes = 512 * 1024

    public enum CommandType: String, Codable, Sendable {
        case hello
        case extensionsList = "extensions.list"
        case runStart = "run.start"
        case runCancel = "run.cancel"
        case runGet = "run.get"
        case eventsSubscribe = "events.subscribe"
        case draftStage = "draft.stage"
        case draftChunk = "draft.chunk"
        case draftFinish = "draft.finish"
        case draftDiscard = "draft.discard"
        case draftInstall = "draft.install"
        case draftRollback = "draft.rollback"
    }

    /// Mã lỗi cố định — client dựa vào mã, không dựa vào câu chữ tiếng Việt.
    public enum ErrorCode: String, Codable, Sendable, Error {
        case unsupportedVersion = "UNSUPPORTED_VERSION"
        case malformedMessage = "MALFORMED_MESSAGE"
        case unknownExtension = "UNKNOWN_EXTENSION"
        case unknownEntrypoint = "UNKNOWN_ENTRYPOINT"
        case unknownRun = "UNKNOWN_RUN"
        case quotaExceeded = "QUOTA_EXCEEDED"
        case draftInvalid = "DRAFT_INVALID"
        case draftMissing = "DRAFT_MISSING"
        case approvalRequired = "APPROVAL_REQUIRED"
        case internalError = "INTERNAL_ERROR"
    }

    public struct Envelope: Codable, Sendable {
        public var version: Int
        public var requestId: String
        public var type: String
        public var payload: Payload?

        public init(version: Int = ExtensionDebugProtocol.version, requestId: String, type: String, payload: Payload? = nil) {
            self.version = version
            self.requestId = requestId
            self.type = type
            self.payload = payload
        }
    }

    /// Union phẳng: mỗi lệnh chỉ đọc những field nó cần. Phẳng thay vì lồng theo `type` để client
    /// TypeScript không phải dựng 13 kiểu rời rạc, và để thêm field mới không phá bản cũ.
    public struct Payload: Codable, Sendable {
        // hello
        public var clientName: String?
        // extensions.list reply
        public var extensions: [ExtensionInfo]?
        // run.start
        public var packageId: String?
        public var entrypoint: String?
        public var keyword: String?
        public var page: Int?
        public var url: String?
        public var scriptFileName: String?
        public var input: String?
        public var pageUrl: String?
        public var sourceMode: String?
        public var sourceRevision: String?
        // run.start reply / run.cancel / run.get
        public var runId: String?
        public var events: [ExtensionDebugEvent]?
        public var droppedCount: Int?
        // draft.*
        public var manifest: ExtensionDraftManifest?
        public var relativePath: String?
        public var chunkIndex: Int?
        public var chunkBase64: String?
        public var isLastChunk: Bool?
        public var issues: [String]?
        // error
        public var code: String?
        public var message: String?
        // hello reply
        public var appVersion: String?
        public var contractVersion: Int?

        public init() {}
    }

    /// Metadata extension trả cho client. **Chỉ** những gì có trong manifest — không đường dẫn tuyệt
    /// đối, không `configJson`.
    public struct ExtensionInfo: Codable, Sendable {
        public let packageId: String
        public let name: String
        public let version: Int
        public let type: String
        /// Khoá khai ở mục `script` của `plugin.json`.
        public let scripts: [String]
        /// Path tương đối của mọi `.js` **có hàm `execute`** ở gốc extension và `src/` — tập file thật
        /// sự chạy được, kể cả script phụ không khai trong `script`. Thêm ở 1.3.348; client cũ bỏ qua
        /// field này nên không phá tương thích.
        public let executableScripts: [String]

        public init(
            packageId: String,
            name: String,
            version: Int,
            type: String,
            scripts: [String],
            executableScripts: [String] = []
        ) {
            self.packageId = packageId
            self.name = name
            self.version = version
            self.type = type
            self.scripts = scripts
            self.executableScripts = executableScripts
        }
    }

    public static func errorEnvelope(requestId: String, code: ErrorCode, message: String) -> Envelope {
        var payload = Payload()
        payload.code = code.rawValue
        payload.message = message
        return Envelope(requestId: requestId, type: "error", payload: payload)
    }
}
