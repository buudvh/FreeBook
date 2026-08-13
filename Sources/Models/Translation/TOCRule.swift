import Foundation

public struct TOCRule: Codable, Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let rule: String
    public let example: String?
    public var enabled: Bool
    public let replace: String
    public let isRegex: Bool

    public var pattern: String { rule }

    public init(
        id: String = UUID().uuidString,
        name: String,
        rule: String,
        example: String? = nil,
        enabled: Bool = true,
        replace: String = "",
        isRegex: Bool = true
    ) {
        self.id = id
        self.name = name
        self.rule = rule
        self.example = example
        self.enabled = enabled
        self.replace = replace
        self.isRegex = isRegex
    }

    public init(
        name: String,
        pattern: String,
        replace: String,
        isRegex: Bool = true
    ) {
        self.id = name
        self.name = name
        self.rule = pattern
        self.example = nil
        self.enabled = true
        self.replace = replace
        self.isRegex = isRegex
    }
}
