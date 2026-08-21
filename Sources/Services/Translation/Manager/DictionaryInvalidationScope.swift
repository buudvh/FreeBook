import Foundation

public enum DictionaryInvalidationScope: Equatable, Sendable {
    case term(word: String, isName: Bool, bookId: String?)
    case config(bookId: String?)
    case globalReload
}
