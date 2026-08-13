import Foundation

public struct TOCImportPreview: Sendable {
    public let rules: [TOCRule]
    public let sourceCount: Int
    public let hasOverlap: Bool

    public init(rules: [TOCRule], sourceCount: Int, hasOverlap: Bool) {
        self.rules = rules
        self.sourceCount = sourceCount
        self.hasOverlap = hasOverlap
    }
}
