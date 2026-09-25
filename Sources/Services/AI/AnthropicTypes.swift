import Foundation

/// Request gửi tới Anthropic Messages API (`/v1/messages`).
public struct AnthropicMessageRequest: Codable, Sendable {
    public struct Message: Codable, Sendable, Equatable {
        public let role: String
        public let content: String

        public init(role: String, content: String) {
            self.role = role
            self.content = content
        }
    }

    /// DTO phản hồi non-streaming từ Anthropic Messages API.
    public struct Response: Codable, Sendable {
        public struct ContentBlock: Codable, Sendable {
            public let type: String?
            public let text: String?

            public init(type: String?, text: String?) {
                self.type = type
                self.text = text
            }
        }

        public let id: String?
        public let type: String?
        public let role: String?
        public let content: [ContentBlock]?

        public init(id: String?, type: String?, role: String?, content: [ContentBlock]?) {
            self.id = id
            self.type = type
            self.role = role
            self.content = content
        }
    }

    /// DTO phân tích cú pháp sự kiện SSE Streaming từ Anthropic (`content_block_delta`).
    public struct StreamDelta: Codable, Sendable {
        public struct Delta: Codable, Sendable {
            public let type: String?
            public let text: String?

            public init(type: String?, text: String?) {
                self.type = type
                self.text = text
            }
        }

        public let type: String?
        public let index: Int?
        public let delta: Delta?

        public init(type: String?, index: Int?, delta: Delta?) {
            self.type = type
            self.index = index
            self.delta = delta
        }
    }

    public let model: String
    public let system: String?
    public let messages: [Message]
    public let max_tokens: Int
    public let temperature: Double?
    public let stream: Bool?

    public init(
        model: String,
        system: String? = nil,
        messages: [Message],
        max_tokens: Int = 4096,
        temperature: Double? = nil,
        stream: Bool? = nil
    ) {
        self.model = model
        self.system = system
        self.messages = messages
        self.max_tokens = max_tokens
        self.temperature = temperature
        self.stream = stream
    }
}

public typealias AnthropicMessageResponse = AnthropicMessageRequest.Response
public typealias AnthropicStreamDelta = AnthropicMessageRequest.StreamDelta
