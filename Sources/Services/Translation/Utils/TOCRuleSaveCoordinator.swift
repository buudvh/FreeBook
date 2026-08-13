import Foundation

public actor TOCRuleSaveCoordinator {
    public static let shared = TOCRuleSaveCoordinator()
    private var previousSaveTask: Task<Bool, Never>? = nil

    public init() {}

    @discardableResult
    public func enqueue(_ rules: [TOCRule]) -> Task<Bool, Never> {
        let currentPrevious = previousSaveTask
        let newSaveTask = Task { () -> Bool in
            _ = await currentPrevious?.value
            return TranslateUtils.saveTOCRules(rules)
        }
        self.previousSaveTask = newSaveTask
        return newSaveTask
    }

    @discardableResult
    public func scheduleSave(_ rules: [TOCRule]) async -> Bool {
        let task = enqueue(rules)
        return await task.value
    }

    public func flush() async {
        _ = await previousSaveTask?.value
    }
}
