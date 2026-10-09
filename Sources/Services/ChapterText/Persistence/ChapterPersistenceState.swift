import Foundation

enum ChapterPersistenceState: Sendable, Equatable {
    case pending
    case persisted
    case failed
}
