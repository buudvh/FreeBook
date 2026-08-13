import Foundation

public struct TOCImportPreview: Sendable {
    public let rules: [TOCRule]
    public let sourceCount: Int
    public let hasOverlap: Bool
    public let importedCount: Int
    public let newCount: Int
    public let updateCount: Int
    public let preservedCount: Int
    public let restoredDefaultCount: Int

    public init(
        rules: [TOCRule],
        sourceCount: Int,
        hasOverlap: Bool,
        importedCount: Int = 0,
        newCount: Int = 0,
        updateCount: Int = 0,
        preservedCount: Int = 0,
        restoredDefaultCount: Int = 0
    ) {
        self.rules = rules
        self.sourceCount = sourceCount
        self.hasOverlap = hasOverlap
        self.importedCount = importedCount
        self.newCount = newCount
        self.updateCount = updateCount
        self.preservedCount = preservedCount
        self.restoredDefaultCount = restoredDefaultCount
    }

    public init(
        importedCount: Int,
        newCount: Int,
        updateCount: Int,
        preservedCount: Int,
        rules: [TOCRule] = []
    ) {
        self.rules = rules
        self.sourceCount = importedCount
        self.hasOverlap = updateCount > 0
        self.importedCount = importedCount
        self.newCount = newCount
        self.updateCount = updateCount
        self.preservedCount = preservedCount
        self.restoredDefaultCount = 0
    }

    public init(
        importedCount: Int,
        restoredDefaultCount: Int,
        rules: [TOCRule] = []
    ) {
        self.rules = rules
        self.sourceCount = importedCount
        self.hasOverlap = false
        self.importedCount = importedCount
        self.newCount = importedCount
        self.updateCount = 0
        self.preservedCount = 0
        self.restoredDefaultCount = restoredDefaultCount
    }
}
