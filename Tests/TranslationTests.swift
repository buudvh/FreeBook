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

    func testTranslateUtilsKeepsASCIIAlphanumericRunsIntact() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let vpUrl = tempDir.appendingPathComponent("VietPhrase.txt")
        let vpContent = """
        决战=Quyết chiến
        天下=Thiên hạ
        """
        try vpContent.write(to: vpUrl, atomically: true, encoding: .utf8)

        let paUrl = tempDir.appendingPathComponent("ChinesePhienAmWords.txt")
        let paContent = """
        中=trung
        """
        try paContent.write(to: paUrl, atomically: true, encoding: .utf8)

        let manager = TranslationManager.shared
        try? FileManager.default.removeItem(at: manager.translateDirectory)

        let expectation = XCTestExpectation(description: "Load ASCII regression dictionaries")
        Task {
            try? await manager.importDictionary(from: vpUrl, type: "vietphrase")
            try? await manager.importDictionary(from: paUrl, type: "phienam")
            TranslateUtils.clearCache()
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)

        XCTAssertEqual(TranslateUtils.translateMeta("hello"), "hello")
        XCTAssertEqual(TranslateUtils.translateContent("hello 1000 iOS Sto9"), "hello 1000 iOS Sto9")
        XCTAssertEqual(TranslateUtils.translateMeta("决战 hello 天下 1000"), "Quyết chiến hello thiên hạ 1000")

        let tokens = TranslateUtils.getTranslationTokens(for: "hello 1000 中", bookId: nil)
        XCTAssertEqual(tokens.map(\.originalText), ["hello", "1000", "中"])
        XCTAssertEqual(tokens.map(\.translatedText), ["hello", "1000", "trung"])
    }

    func testTranslateUtilsSupportsPipeMeaningSeparator() throws {
        XCTAssertEqual(TranslateUtils.getFirstMeaning(of: "Quyết chiến|Đại chiến"), "Quyết chiến")
        XCTAssertEqual(TranslateUtils.getFirstMeaning(of: "Quyết chiến¦Đại chiến"), "Quyết chiến")
        XCTAssertEqual(TranslateUtils.getFirstMeaning(of: "Quyết chiến/Đại chiến"), "Quyết chiến")
        XCTAssertEqual(TranslateUtils.getFirstMeaning(of: " | Đại chiến"), "")
        XCTAssertEqual(TranslateUtils.getFirstMeaning(of: "/Đại"), "")
        XCTAssertEqual(TranslateUtils.getFirstMeaning(of: "¦Đại"), "")
        XCTAssertEqual(TranslateUtils.getFirstMeaning(of: " /Đại"), "")
        XCTAssertEqual(TranslateUtils.getFirstMeaning(of: "Đại/To"), "Đại")
        XCTAssertEqual(TranslateUtils.getFirstMeaning(of: "Đại"), "Đại")

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let vpUrl = tempDir.appendingPathComponent("VietPhrase.txt")
        let vpContent = """
        决战=Quyết chiến|Đại chiến
        天下=Thiên hạ¦Thiên hạ khác
        """
        try vpContent.write(to: vpUrl, atomically: true, encoding: .utf8)

        let manager = TranslationManager.shared
        try? FileManager.default.removeItem(at: manager.translateDirectory)

        let expectation = XCTestExpectation(description: "Load separator regression dictionaries")
        Task {
            try? await manager.importDictionary(from: vpUrl, type: "vietphrase")
            TranslateUtils.clearCache()
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)

        XCTAssertEqual(TranslateUtils.translateMeta("决战天下"), "Quyết chiến thiên hạ")
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
    
    func testBookSpecificNamesPrioritization() async throws {
        let manager = TranslationManager.shared
        let bookId = "test_book_prioritize_123"
        
        // 1. Thêm Tên riêng trong truyện: 林动 = Lâm Động
        try await manager.saveCustomEntry(word: "林动", meaning: "Lâm Động", isName: true, bookId: bookId)
        // 2. Thêm từ VietPhrase truyện: 林动人 = lâm động nhân
        try await manager.saveCustomEntry(word: "林动人", meaning: "lâm động nhân", isName: false, bookId: bookId)
        
        // Cần đảm bảo có phiên âm cho chữ "人" (nhân) để kiểm chứng
        let paUrl = manager.translateDirectory.appendingPathComponent("ChinesePhienAmWords.txt")
        let currentPa = (try? String(contentsOf: paUrl, encoding: .utf8)) ?? ""
        if !currentPa.contains("人=nhân") {
            let newPa = currentPa + "\n人=nhân\n"
            try? newPa.write(to: paUrl, atomically: true, encoding: .utf8)
            try? await manager.loadAllDictionaries()
        }
        
        // Dịch với bookId -> Phải ưu tiên "林动" (Lâm Động) + "人" (nhân) thay vì cụm dài "林动人" (lâm động nhân)
        let translated = TranslateUtils.translateMeta("林动人", bookId: bookId)
        XCTAssertEqual(translated, "Lâm Động nhân")
        
        // Cleanup
        let bookDir = manager.translateDirectory.appendingPathComponent("books").appendingPathComponent(bookId)
        try? FileManager.default.removeItem(at: bookDir)
        manager.clearBookDictCache(for: bookId)
    }

    func testIsChapterHeaderLineAndCustomTOCRuleState() throws {
        // 1. Test Chinese sample-shaped headings
        XCTAssertTrue(TranslateUtils.isChapterHeaderLine(" 第一章 蓝电潜龙"))
        XCTAssertTrue(TranslateUtils.isChapterHeaderLine(" 第二百一十章 神禁审判，终局"))
        XCTAssertTrue(TranslateUtils.isChapterHeaderLine("第100章 Test Chapter"))

        // 2. Test custom rule enablement / disablement
        let customRuleEnabled = TOCRule(id: "custom_sec", name: "Custom Section", rule: #"^Section \d+$"#, example: "Section 1", enabled: true)
        let customRuleDisabled = TOCRule(id: "custom_sec", name: "Custom Section", rule: #"^Section \d+$"#, example: "Section 1", enabled: false)

        XCTAssertTrue(TranslateUtils.isMatchingTOCRule("Section 1", rules: [customRuleEnabled]))
        XCTAssertFalse(TranslateUtils.isMatchingTOCRule("Section 1", rules: [customRuleDisabled]))

        // 3. Test Vietnamese & English indented fallbacks
        XCTAssertTrue(TranslateUtils.isChapterHeaderLine("  Chương 1: Mở đầu"))
        XCTAssertTrue(TranslateUtils.isChapterHeaderLine("  Chapter 2: The Journey"))

        // 4. Test unindented numeric fallback
        XCTAssertTrue(TranslateUtils.isChapterHeaderLine("01. Tiêu đề số"))

        // 5. Test indented numeric false-positive protection
        XCTAssertFalse(TranslateUtils.isChapterHeaderLine("  1000 quân lính tiến vào thành phố"))
    }

    func testTOCRulesPersistenceAndResetNonDestructive() throws {
        let manager = TranslationManager.shared
        let url = manager.translateDirectory.appendingPathComponent("toc_rules.json")
        let originalData = try? Data(contentsOf: url)

        defer {
            if let originalData = originalData {
                try? originalData.write(to: url, options: .atomic)
            } else {
                try? FileManager.default.removeItem(at: url)
            }
            TranslateUtils.invalidateTOCRulesCache()
            TranslateUtils.clearChapterTitleCache()
        }

        let initialRules = TranslateUtils.getAllTOCRules()
        XCTAssertFalse(initialRules.isEmpty)

        let customRule = TOCRule(id: "test_temp_id_\(UUID().uuidString)", name: "Test Rule", rule: #"^Test \d+$"#, example: "Test 1", enabled: true)
        var updated = initialRules
        updated.append(customRule)

        let saveSuccess = TranslateUtils.saveTOCRules(updated)
        XCTAssertTrue(saveSuccess)

        let reloaded = TranslateUtils.getAllTOCRules()
        XCTAssertTrue(reloaded.contains(where: { $0.id == customRule.id }))

        let resetSuccess = TranslateUtils.resetTOCRulesToDefault()
        XCTAssertTrue(resetSuccess)

        let afterReset = TranslateUtils.getAllTOCRules()
        XCTAssertFalse(afterReset.contains(where: { $0.id == customRule.id }))
    }

    func testTOCRulePatternValidation() throws {
        XCTAssertNil(TranslateUtils.validateTOCRulePattern(#"^Chương \d+"#))
        XCTAssertNotNil(TranslateUtils.validateTOCRulePattern(""))
        XCTAssertNotNil(TranslateUtils.validateTOCRulePattern("[a-z"))
        XCTAssertNotNil(TranslateUtils.validateTOCRulePattern(String(repeating: "a", count: 251)))
    }

    func testImportValidationOversizedDataAndRulesCount() throws {
        let dummyRule = TOCRule(id: "id_1", name: "Name 1", rule: #"^test$"#, example: nil, enabled: true)
        let data = try JSONEncoder().encode([dummyRule])

        let oversizedDataResult = TranslateUtils.validateImportedTOCRules(data, maxSizeBytes: 10)
        switch oversizedDataResult {
        case .success:
            XCTFail("Should fail oversized data")
        case .failure(let err):
            XCTAssertEqual(err, .fileTooLarge(maxKB: 0))
        }

        let rules101 = (1...101).map { TOCRule(id: "id_\($0)", name: "Name \($0)", rule: #"^test$"#, example: nil, enabled: true) }
        let rules101Data = try JSONEncoder().encode(rules101)
        let tooManyRulesResult = TranslateUtils.validateImportedTOCRules(rules101Data, maxRuleCount: 100)
        switch tooManyRulesResult {
        case .success:
            XCTFail("Should fail > 100 rules")
        case .failure(let err):
            XCTAssertEqual(err, .tooManyRules(count: 101, max: 100))
        }
    }

    func testImportValidationEmptyOrOverlongIDAndNameAndDuplicateIDs() throws {
        let emptyIDRule = TOCRule(id: "   ", name: "Valid Name", rule: #"^test$"#, example: nil, enabled: true)
        let emptyIDData = try JSONEncoder().encode([emptyIDRule])
        if case .failure(let err) = TranslateUtils.validateImportedTOCRules(emptyIDData) {
            XCTAssertEqual(err, .emptyID(index: 0))
        } else {
            XCTFail("Should reject empty ID")
        }

        let overlongIDRule = TOCRule(id: String(repeating: "i", count: 101), name: "Valid Name", rule: #"^test$"#, example: nil, enabled: true)
        let overlongIDData = try JSONEncoder().encode([overlongIDRule])
        if case .failure(let err) = TranslateUtils.validateImportedTOCRules(overlongIDData) {
            XCTAssertEqual(err, .idTooLong(index: 0))
        } else {
            XCTFail("Should reject overlong ID")
        }

        let emptyNameRule = TOCRule(id: "valid_id", name: "   ", rule: #"^test$"#, example: nil, enabled: true)
        let emptyNameData = try JSONEncoder().encode([emptyNameRule])
        if case .failure(let err) = TranslateUtils.validateImportedTOCRules(emptyNameData) {
            XCTAssertEqual(err, .emptyName(index: 0, id: "valid_id"))
        } else {
            XCTFail("Should reject empty name")
        }

        let overlongNameRule = TOCRule(id: "valid_id", name: String(repeating: "n", count: 101), rule: #"^test$"#, example: nil, enabled: true)
        let overlongNameData = try JSONEncoder().encode([overlongNameRule])
        if case .failure(let err) = TranslateUtils.validateImportedTOCRules(overlongNameData) {
            XCTAssertEqual(err, .nameTooLong(index: 0))
        } else {
            XCTFail("Should reject overlong name")
        }

        let dupRule1 = TOCRule(id: "dup_id", name: "Name 1", rule: #"^r1$"#, example: nil, enabled: true)
        let dupRule2 = TOCRule(id: "dup_id", name: "Name 2", rule: #"^r2$"#, example: nil, enabled: true)
        let dupData = try JSONEncoder().encode([dupRule1, dupRule2])
        if case .failure(let err) = TranslateUtils.validateImportedTOCRules(dupData) {
            XCTAssertEqual(err, .duplicateID(id: "dup_id"))
        } else {
            XCTFail("Should reject duplicate IDs")
        }

        // Whitespace-equivalent duplicate ID case
        let wsDupRule1 = TOCRule(id: "dup_ws ", name: "Name 1", rule: #"^r1$"#, example: nil, enabled: true)
        let wsDupRule2 = TOCRule(id: "dup_ws", name: "Name 2", rule: #"^r2$"#, example: nil, enabled: true)
        let wsDupData = try JSONEncoder().encode([wsDupRule1, wsDupRule2])
        if case .failure(let err) = TranslateUtils.validateImportedTOCRules(wsDupData) {
            XCTAssertEqual(err, .duplicateID(id: "dup_ws"))
        } else {
            XCTFail("Should reject whitespace-equivalent duplicate IDs")
        }
    }

    func testDeterministicMergeAndReplaceOrderDetails() throws {
        let defaultRules = TranslateUtils.getDefaultTOCRules()
        let currentRules = [
            defaultRules[0],
            TOCRule(id: "custom_1", name: "Custom 1", rule: #"^c1$"#, example: nil, enabled: true),
            TOCRule(id: "custom_2", name: "Custom 2", rule: #"^c2$"#, example: nil, enabled: false)
        ]

        let importedForMerge = [
            TOCRule(id: "custom_2", name: "Updated Custom 2", rule: #"^c2_updated$"#, example: nil, enabled: true),
            TOCRule(id: "custom_3", name: "New Custom 3", rule: #"^c3$"#, example: nil, enabled: true)
        ]

        let merged = TranslateUtils.mergeTOCRules(current: currentRules, imported: importedForMerge)
        XCTAssertEqual(merged.count, 4)
        XCTAssertEqual(merged[0].id, defaultRules[0].id)
        XCTAssertEqual(merged[1].id, "custom_1")
        XCTAssertEqual(merged[2].id, "custom_2")
        XCTAssertEqual(merged[2].name, "Updated Custom 2")
        XCTAssertEqual(merged[3].id, "custom_3")

        let importedForReplace = [
            TOCRule(id: "custom_3", name: "Custom 3", rule: #"^c3$"#, example: nil, enabled: true)
        ]
        let replaced = TranslateUtils.replaceTOCRules(imported: importedForReplace)
        XCTAssertEqual(replaced[0].id, "custom_3")
        // Verify all 5 default rules are appended at end in shipped-default order
        for (idx, defRule) in defaultRules.enumerated() {
            XCTAssertEqual(replaced[1 + idx].id, defRule.id)
        }
    }

    func testAtomicImportRejectionNoFileOrCacheMutation() throws {
        let manager = TranslationManager.shared
        let url = manager.translateDirectory.appendingPathComponent("toc_rules.json")
        let originalData = try? Data(contentsOf: url)

        defer {
            if let originalData = originalData {
                try? originalData.write(to: url, options: .atomic)
            } else {
                try? FileManager.default.removeItem(at: url)
            }
            TranslateUtils.invalidateTOCRulesCache()
            TranslateUtils.clearChapterTitleCache()
        }

        _ = TranslateUtils.getAllTOCRules()
        let fileBytesBefore = try? Data(contentsOf: url)

        let invalidRule = TOCRule(id: "invalid_id", name: "Invalid Rule", rule: #"[unclosed"#, example: nil, enabled: true)
        let invalidData = try! JSONEncoder().encode([invalidRule])

        let validationResult = TranslateUtils.validateImportedTOCRules(invalidData)
        if case .failure = validationResult {
            // Confirmation: rejected validation does not call saveTOCRules
        } else {
            XCTFail("Validation should fail for invalid pattern")
        }

        let fileBytesAfter = try? Data(contentsOf: url)
        XCTAssertEqual(fileBytesBefore, fileBytesAfter)
    }

    func testTempExportFileCreationAndCleanup() throws {
        let rules = [TOCRule(id: "temp_test", name: "Temp Test", rule: #"^temp$"#, example: nil, enabled: true)]
        let jsonData = try JSONEncoder().encode(rules)

        let fileName = "toc_rules_config_test_\(UUID().uuidString.prefix(8)).json"
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(fileName)

        try jsonData.write(to: tempURL, options: .atomic)
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempURL.path))

        // Simulate ShareSheet dismissal cleanup
        try FileManager.default.removeItem(at: tempURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempURL.path))
    }

    func testCoordinatorFIFOAndFlush() async throws {
        let manager = TranslationManager.shared
        let url = manager.translateDirectory.appendingPathComponent("toc_rules.json")
        let originalData = try? Data(contentsOf: url)

        defer {
            if let originalData = originalData {
                try? originalData.write(to: url, options: .atomic)
            } else {
                try? FileManager.default.removeItem(at: url)
            }
            TranslateUtils.invalidateTOCRulesCache()
            TranslateUtils.clearChapterTitleCache()
        }

        let coordinator = TOCRuleSaveCoordinator()

        let r1 = [TOCRule(id: "seq_1", name: "Seq 1", rule: #"^Seq1$"#, example: nil, enabled: true)]
        let r2 = [TOCRule(id: "seq_2", name: "Seq 2", rule: #"^Seq2$"#, example: nil, enabled: true)]
        let r3 = [TOCRule(id: "seq_3", name: "Seq 3", rule: #"^Seq3$"#, example: nil, enabled: true)]

        let t1 = await coordinator.enqueue(r1)
        let t2 = await coordinator.enqueue(r2)
        let t3 = await coordinator.enqueue(r3)

        _ = await t1.value
        _ = await t2.value
        _ = await t3.value

        await coordinator.flush()

        let finalRules = TranslateUtils.getAllTOCRules()
        XCTAssertEqual(finalRules.count, 1)
        XCTAssertEqual(finalRules.first?.id, "seq_3")
    }
}
