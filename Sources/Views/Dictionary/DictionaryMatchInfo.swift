import Foundation

struct DictionaryMatchInfo: Identifiable, Equatable, Sendable {
    var id = UUID()
    let source: String
    let translation: String
}
