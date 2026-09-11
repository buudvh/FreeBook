import Foundation
import Observation

@MainActor @Observable
final class ReaderDefinitionSession {
    var identity = UUID()
    var requestID = UUID()
    var meaningRevision = 0
    var loading = false
    var loadingRules = false
    var hasRules = false
    var rulesEnabled = false
    var saving = false
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
    }

    func cancel() {
        requestID = UUID()
        task?.cancel()
        task = nil
        ruleTask?.cancel()
        ruleTask = nil
        loading = false
        loadingRules = false
    }
}
