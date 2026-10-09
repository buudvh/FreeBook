import Foundation

struct PersistedChapterSnapshot: Sendable, Equatable {
    let title: String
    let url: String
    let index: Int
    let host: String?
    let content: String
}
