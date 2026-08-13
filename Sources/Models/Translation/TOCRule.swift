import Foundation

public struct TOCRule: Codable, Identifiable, Sendable, Equatable {
    public var id: String { name }
    public let name: String
    public let pattern: String
    public let replace: String
    public let isRegex: Bool

    public init(name: String, pattern: String, replace: String, isRegex: Bool = true) {
        self.name = name
        self.pattern = pattern
        self.replace = replace
        self.isRegex = isRegex
    }
}
