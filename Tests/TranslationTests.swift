import XCTest
@testable import FreeBook

final class TranslationTests: XCTestCase {
    
    func testTextDictionaryMatching() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        let dictUrl = tempDir.appendingPathComponent("VietPhrase.txt")
        let dictContent = """
        一=Một
        十二=Mười hai
        第一百二十=Một trăm hai mươi
        决战=Quyết chiến
        """
        try dictContent.write(to: dictUrl, atomically: true, encoding: .utf8)
        
        let dict = TextDictionary()
        try dict.load(from: dictUrl)
        
        XCTAssertTrue(dict.isLoaded)
        
        let match1 = dict.findLongestMatch(text: "决战天下", startIndex: 0)
        XCTAssertNotNil(match1)
        XCTAssertEqual(match1?.length, 2)
        XCTAssertEqual(match1?.value, "Quyết chiến")
        
        let match2 = dict.findLongestMatch(text: "第一百二十章", startIndex: 0)
        XCTAssertNotNil(match2)
        XCTAssertEqual(match2?.length, 6)
        XCTAssertEqual(match2?.value, "Một trăm hai mươi")
    }
    
    func testTranslateUtilsNormalisation() throws {
        XCTAssertTrue(TranslateUtils.containsChinese("第1章 决战"))
        XCTAssertFalse(TranslateUtils.containsChinese("Chương 1: Quyết chiến"))
        
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        let vpUrl = tempDir.appendingPathComponent("VietPhrase.txt")
        let vpContent = """
        决战=Quyết chiến
        天下=Thiên hạ
        """
        try vpContent.write(to: vpUrl, atomically: true, encoding: .utf8)
        
        let paUrl = tempDir.appendingPathComponent("ChinesePhienAmWords.txt")
        let paContent = """
        一=nhất
        章=chương
        """
        try paContent.write(to: paUrl, atomically: true, encoding: .utf8)
        
        let manager = TranslationManager.shared
        try? FileManager.default.removeItem(at: manager.translateDirectory)
        
        let expectation = XCTestExpectation(description: "Load dictionaries")
        Task {
            try? await manager.importDictionary(from: vpUrl, type: "vietphrase")
            try? await manager.importDictionary(from: paUrl, type: "phienam")
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 5.0)
        
        UserDefaults.standard.set(true, forKey: "isTranslationEnabled")
        
        let translatedMeta = TranslateUtils.translateMeta("决战天下")
        XCTAssertEqual(translatedMeta, "Quyết chiến thiên hạ")
    }
    
    func testTOCRulesMatching() throws {
        let translatedChapter1 = TranslateUtils.translateChapterTitle("第1章 Thất Sát Kiếm cùng tiên thiên đầy hồn lực")
        XCTAssertEqual(translatedChapter1, "Chương 1: Thất Sát Kiếm cùng tiên thiên đầy hồn lực")
        
        let translatedChapter2 = TranslateUtils.translateChapterTitle("第一百二十章 决战")
        XCTAssertEqual(translatedChapter2, "Chương 120: Quyết chiến")
    }
    
    func testBookSpecificDictionariesAndSaving() async throws {
        let manager = TranslationManager.shared
        let bookId = "test_book_123"
        
        try await manager.saveCustomEntry(word: "决战", meaning: "Đại chiến sinh tử", isName: true, bookId: bookId)
        try await manager.saveCustomEntry(word: "天下", meaning: "Thế gian", isName: false, bookId: bookId)
        
        let dicts = manager.getBookDictionaries(for: bookId)
        XCTAssertNotNil(dicts.names)
        XCTAssertNotNil(dicts.vietPhrase)
        
        let translatedWithBook = TranslateUtils.translateMeta("决战天下", bookId: bookId)
        XCTAssertEqual(translatedWithBook, "Đại chiến sinh tử thế gian")
        
        let translatedGlobal = TranslateUtils.translateMeta("决战天下", bookId: nil)
        XCTAssertEqual(translatedGlobal, "Quyết chiến thiên hạ")
        
        let bookDir = manager.translateDirectory.appendingPathComponent("books").appendingPathComponent(bookId)
        try? FileManager.default.removeItem(at: bookDir)
        manager.clearBookDictCache(for: bookId)
    }
}
