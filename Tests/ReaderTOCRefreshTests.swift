import XCTest
import SwiftData
@testable import FreeBook

@available(iOS 17.0, *)
final class ReaderTOCRefreshTests: XCTestCase {
    @MainActor
    func testReaderViewModel_updateChapterSnapshot_expandsTotalCountWhenRefreshed() throws {
        let schema = Schema([Book.self, Chapter.self])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)

        let vm = ReaderViewModel(
            bookId: "test_book_1",
            extensionPackageId: "",
            initialChapterIndex: 99,
            initialParagraphIndex: -1,
            totalChaptersCount: 100,
            modelContext: context
        )
        XCTAssertEqual(vm.totalChaptersCount, 100)

        // Directly verify ReaderViewModel's updateChapterSnapshot updates totalChaptersCount from 100 to 110
        vm.updateChapterSnapshot(totalCount: 110, onlineChapters: [])

        XCTAssertEqual(vm.totalChaptersCount, 110)
    }
}
