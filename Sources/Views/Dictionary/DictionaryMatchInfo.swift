import Foundation

struct DictionaryMatchInfo: Identifiable, Equatable {
    var id = UUID()
    let source: String
    let translation: String
}
