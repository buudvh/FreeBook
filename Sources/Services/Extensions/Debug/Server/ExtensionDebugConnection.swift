import Foundation
import Network

/// Một kết nối WebSocket của debug server. Ở MVP chỉ tồn tại **một** instance tại một thời điểm.
///
/// Lớp này chỉ làm khung truyền: nhận message → giao cho handler, và gửi `Envelope` đã encode. Nó
/// **không** biết gì về nội dung lệnh — việc đó thuộc `ExtensionDebugCommandRouter`, để đường
/// "chưa pair thì không được list/run" chỉ có đúng một chỗ cưỡng chế.
public final class ExtensionDebugConnection: @unchecked Sendable {
    public typealias MessageHandler = @Sendable (Data) -> Void
    public typealias CloseHandler = @Sendable (String?) -> Void

    private let connection: NWConnection
    private let queue: DispatchQueue
    private let onMessage: MessageHandler
    private let onClose: CloseHandler
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = []
        return encoder
    }()
    private let lock = NSLock()
    private var isClosed = false

    public init(
        connection: NWConnection,
        queue: DispatchQueue,
        onMessage: @escaping MessageHandler,
        onClose: @escaping CloseHandler
    ) {
        self.connection = connection
        self.queue = queue
        self.onMessage = onMessage
        self.onClose = onClose
    }

    public func start() {
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.receiveNext()
            case .failed(let error):
                self?.finish(reason: error.localizedDescription)
            case .cancelled:
                self?.finish(reason: nil)
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    public func send(_ envelope: ExtensionDebugProtocol.Envelope) {
        guard let data = try? encoder.encode(envelope) else { return }
        sendRaw(data)
    }

    private func sendRaw(_ data: Data) {
        lock.lock()
        let closed = isClosed
        lock.unlock()
        guard !closed else { return }

        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "extdebug", metadata: [metadata])
        connection.send(
            content: data,
            contentContext: context,
            isComplete: true,
            completion: .contentProcessed { _ in }
        )
    }

    public func close(reason: String?) {
        lock.lock()
        let alreadyClosed = isClosed
        isClosed = true
        lock.unlock()
        guard !alreadyClosed else { return }
        connection.cancel()
        onClose(reason)
    }

    private func finish(reason: String?) {
        lock.lock()
        let alreadyClosed = isClosed
        isClosed = true
        lock.unlock()
        guard !alreadyClosed else { return }
        onClose(reason)
    }

    /// Vòng nhận: `receiveMessage` trả **một** frame WebSocket hoàn chỉnh mỗi lần, nên không phải tự
    /// ghép buffer. Message quá trần thì đóng kết nối thay vì cố xử lý.
    private func receiveNext() {
        connection.receiveMessage { [weak self] data, context, _, error in
            guard let self else { return }
            if let error {
                self.finish(reason: error.localizedDescription)
                return
            }
            if let metadata = context?.protocolMetadata(definition: NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata,
               metadata.opcode == .close {
                self.close(reason: "Client đóng kết nối")
                return
            }
            if let data {
                if data.count > ExtensionDebugProtocol.maxIncomingMessageBytes {
                    self.close(reason: "Message vượt trần \(ExtensionDebugProtocol.maxIncomingMessageBytes) byte")
                    return
                }
                self.onMessage(data)
            }
            self.receiveNext()
        }
    }
}
