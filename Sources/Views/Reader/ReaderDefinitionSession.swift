import Foundation
import Observation

@MainActor @Observable
final class ReaderDefinitionSession {
    struct SelectionSnapshot: Equatable {
        let sentence: String
        let word: String
        let range: NSRange
        let mode: String
        let convertTraditional: Bool
        let generation: Int
    }

    var identity = UUID()
    var requestID = UUID()
    var meaningRevision = 0
    var loading = false
    var loadingRules = false
    var hasRules = false
    var rulesEnabled = false
    var saving = false
    var displayedSnapshot: SelectionSnapshot?
    var loadingSnapshot: SelectionSnapshot?
    @ObservationIgnored let worker = ReaderDefinitionWorker()
    @ObservationIgnored var task: Task<Void, Never>?
    @ObservationIgnored var ruleTask: Task<Void, Never>?
    @ObservationIgnored var lastSelection: (chapter: Int, item: ParagraphItem, range: NSRange, generation: Int, mapped: NSRange)?

    func begin() {
        cancel()
        identity = UUID()
        meaningRevision = 0
        saving = false
        hasRules = false
        displayedSnapshot = nil
        loadingSnapshot = nil
    }

    func cancel() {
        requestID = UUID()
        task?.cancel()
        task = nil
        ruleTask?.cancel()
        ruleTask = nil
        loading = false
        loadingRules = false
        loadingSnapshot = nil
    }
}
