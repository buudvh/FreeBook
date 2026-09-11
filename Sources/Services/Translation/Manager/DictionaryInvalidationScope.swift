import Foundation

public enum DictionaryInvalidationScope: Equatable, Sendable {
    case term(word: String, isName: Bool, bookId: String?)
    case config(bookId: String?)
    case globalReload

    func affects(bookId: String) -> Bool {
        switch self {
        case .term(_, _, let scoped), .config(let scoped): return scoped == nil || scoped == bookId
        case .globalReload: return true
        }
    }
}
