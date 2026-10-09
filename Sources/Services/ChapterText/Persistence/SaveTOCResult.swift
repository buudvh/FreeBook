import Foundation

struct SaveTOCResult: Sendable, Equatable {
    let inserted: Int
    let updated: Int
    let deleted: Int
    let totalChapters: Int
}
