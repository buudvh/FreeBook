import Foundation

public enum ChapterRepositoryFactory {
    public static func make(dbURL: URL? = nil) async throws -> any ChapterRepositoryProtocol {
        return try await ChapterSQLiteRepository.make(customURL: dbURL)
    }
}
