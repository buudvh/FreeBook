import Foundation

/// Các lời gọi Telegram Bot API không gửi file. Dùng để xác minh token và chat trước khi bật sao lưu.
public actor TelegramBotClient {
    public static let shared = TelegramBotClient()

    public enum Failure: LocalizedError {
        case notConfigured
        case invalidResponse
        case rejected(String)

        public var errorDescription: String? {
            switch self {
            case .notConfigured: return "Chưa nhập đủ Bot Token và Chat ID"
            case .invalidResponse: return "Telegram trả về dữ liệu không hợp lệ"
            case .rejected(let message): return "Telegram từ chối: \(message)"
            }
        }
    }

    private struct Envelope<Result: Decodable>: Decodable {
        let ok: Bool
        let result: Result?
        let description: String?
    }

    private struct Bot: Decodable { let username: String? }
    private struct Chat: Decodable { let title: String?; let username: String?; let firstName: String? }

    private init() {}

    public func validateConfiguration() async throws -> String {
        guard let token = TelegramTokenStore.load(), !TelegramConfiguration.chatID.isEmpty else {
            throw Failure.notConfigured
        }
        let bot: Bot = try await call(method: "getMe", token: token, queryItems: [])
        let chat: Chat = try await call(
            method: "getChat",
            token: token,
            queryItems: [URLQueryItem(name: "chat_id", value: TelegramConfiguration.chatID)]
        )
        let botName = bot.username.map { "@\($0)" } ?? "bot"
        let chatName = chat.title ?? chat.username.map { "@\($0)" } ?? chat.firstName ?? TelegramConfiguration.chatID
        return "Đã kết nối \(botName) với \(chatName)"
    }

    private func call<Result: Decodable>(
        method: String,
        token: String,
        queryItems: [URLQueryItem]
    ) async throws -> Result {
        var components = URLComponents(string: "https://api.telegram.org/bot\(token)/\(method)")!
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 30
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let envelope = try? JSONDecoder().decode(Envelope<Result>.self, from: data) else {
            throw Failure.invalidResponse
        }
        guard envelope.ok, let result = envelope.result else {
            throw Failure.rejected(envelope.description ?? "Lỗi không xác định")
        }
        return result
    }
}
