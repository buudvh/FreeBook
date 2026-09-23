import Foundation

/// Request gửi tới OpenAI /chat/completions.
public struct OpenAIChatRequest: Codable, Sendable {
    public struct Message: Codable, Sendable {
        public let role: String
        public let content: String?
        public let tool_calls: [ToolCall]?

        public init(role: String, content: String?, tool_calls: [ToolCall]? = nil) {
            self.role = role
            self.content = content
            self.tool_calls = tool_calls
        }
    }

    public struct Tool: Codable, Sendable {
        public struct FunctionDefinition: Codable, Sendable {
            public let name: String
            public let description: String
            public let parameters: [String: AnyCodable]

            public init(name: String, description: String, parameters: [String: AnyCodable]) {
                self.name = name
                self.description = description
                self.parameters = parameters
            }
        }

        public let type: String
        public let function: FunctionDefinition

        public init(type: String = "function", function: FunctionDefinition) {
            self.type = type
            self.function = function
        }
    }

    /// DTO biểu diễn Tool Call trả về từ model.
    public struct ToolCall: Codable, Sendable, Equatable {
        public struct FunctionCall: Codable, Sendable, Equatable {
            public let name: String
            public let arguments: String
        }

        public let id: String?
        public let type: String?
        public let function: FunctionCall

        public init(id: String?, type: String? = "function", function: FunctionCall) {
            self.id = id
            self.type = type
            self.function = function
        }
    }

    /// Bọc giá trị Any cho JSON schema parameters.
    public struct AnyCodable: Codable, Sendable, Equatable {
        public let value: String

        public init(_ value: String) {
            self.value = value
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            self.value = (try? container.decode(String.self)) ?? ""
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(value)
        }
    }

    public let model: String
    public let messages: [Message]
    public let temperature: Double?
    public let stream: Bool?
    public let tools: [Tool]?

    public init(
        model: String,
        messages: [Message],
        temperature: Double? = nil,
        stream: Bool? = nil,
        tools: [Tool]? = nil
    ) {
        self.model = model
        self.messages = messages
        self.temperature = temperature
        self.stream = stream
        self.tools = tools
    }
}
