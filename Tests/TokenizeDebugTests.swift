import XCTest
@testable import FreeBook

/// Debug tests để điều tra lỗi tokenize split "仿佛" thành 2 token đơn lẻ
/// dù "仿佛" có trong VP dict.
///
/// # Cách đọc kết quả
/// - Test 1 PASS, Test 2 FAIL → bug xảy ra khi dict có entry dài hơn "仿佛X"
/// - Nhìn `VPScanEntry.longestVPLen` để biết `findLongestMatch` trả về bao nhiêu chars
/// - Nhìn allVPCandidates vs selectedVPs để biết VP nào bị reject ở Bước 4
final class TokenizeDebugTests: XCTestCase {

    // MARK: - Helpers

    /// Tạo VP dict TXT tạm từ string content, compile thành DAT, import vào TranslationManager.
    private func loadVietPhrase(_ content: String) async throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TokenizeDebugTests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let vpUrl = tmpDir.appendingPathComponent("VietPhrase.txt")
        try content.write(to: vpUrl, atomically: true, encoding: .utf8)

        // Xoá translate dir cũ để đảm bảo clean state
        let manager = TranslationManager.shared
        try? FileManager.default.removeItem(at: manager.translateDirectory)

        try await manager.importDictionary(from: vpUrl, type: "vietphrase")
        TranslateUtils.clearCache()
    }

    // MARK: - Test 1: Không có entry dài → 仿佛 PHẢI được group đúng

    func test_仿佛_basicGrouping_noLongerEntries() async throws {
        // VP dict: chỉ có 2-char "仿佛" và các single-char / VP ngắn khác
        // KHÔNG có entry nào dài hơn bắt đầu bằng "仿佛"
        try await loadVietPhrase("""
        仿佛=phảng phất/dường như
        仿=phỏng theo
        在=trong/ở tại
        一瞬间=nháy mắt
        一=một
        """)

        let trace = TranslateUtils.tokenizeWithTrace("仿佛在一瞬间")
        print("\n[Test 1 - No Longer Entries]\n\(trace.description)\n")

        // 仿佛 phải là 1 token (không split)
        XCTAssertTrue(
            trace.finalTokens.contains("仿佛"),
            "Expect '仿佛' là 1 token. Tokens thực tế: \(trace.finalTokens)"
        )
        // Và không xuất hiện riêng lẻ
        XCTAssertFalse(
            trace.finalTokens.contains("仿") && trace.finalTokens.contains("佛"),
            "Expect '仿' và '佛' KHÔNG xuất hiện riêng lẻ cùng nhau. Tokens: \(trace.finalTokens)"
        )
    }

    // MARK: - Test 2: Có entry dài "仿佛X" → kiểm tra 仿佛 có bị ảnh hưởng không

    func test_仿佛_withLongerConflictEntry() async throws {
        // VP dict: có "仿佛如" (3-char, bắt đầu bằng "仿佛") nhưng KHÔNG có "仿佛在"
        // → checkText="仿佛在一瞬间": sau '佛', Trie thử '在', không match "仿佛在"
        //   → break → trả về matchLen=2 → VPCandidate "仿佛" (length=2) ✓
        try await loadVietPhrase("""
        仿佛=phảng phất/dường như
        仿佛如=giống như/tựa như
        仿=phỏng theo
        在=trong/ở tại
        一瞬间=nháy mắt
        一=một
        """)

        let trace = TranslateUtils.tokenizeWithTrace("仿佛在一瞬间")
        print("\n[Test 2 - With 仿佛如 entry]\n\(trace.description)\n")

        XCTAssertTrue(
            trace.finalTokens.contains("仿佛"),
            "Expect '仿佛' là 1 token dù có entry 仿佛如. Tokens: \(trace.finalTokens)"
        )
    }

    // MARK: - Test 3: Có entry "仿佛在" → VP candidate sẽ là length=3, xung đột "在" đơn lẻ

    func test_仿佛_withConflictingLongerVP() async throws {
        // VP dict: có cả "仿佛=phảng phất" VÀ "仿佛在=tựa như trong" (3-char)
        // → checkText="仿佛在一瞬间": findLongestMatch trả về length=3 cho "仿佛在"
        // → VPCandidate(0..3, length=3) thay vì (0..2, length=2)
        // → "仿佛" bị tách sai? Hay "仿佛在" được chọn đúng?
        try await loadVietPhrase("""
        仿佛=phảng phất/dường như
        仿佛在=tựa như trong
        仿=phỏng theo
        在=trong/ở tại
        一瞬间=nháy mắt
        一=một
        """)

        let trace = TranslateUtils.tokenizeWithTrace("仿佛在一瞬间")
        print("\n[Test 3 - With 仿佛在 (3-char) entry]\n\(trace.description)\n")

        // Ghi nhận thực tế: 仿佛 có được group không? Và VP nào được chọn?
        let vpTexts = trace.selectedVPs.map { $0.text }
        print("[Test 3] Selected VP texts: \(vpTexts)")
        print("[Test 3] Final tokens: \(trace.finalTokens)")

        // Kiểm tra VP candidate length tại position 0
        if let vpAt0 = trace.allVPCandidates.first(where: { $0.range.lowerBound == 0 }) {
            print("[Test 3] VP candidate at pos=0: '\(vpAt0.text)' length=\(vpAt0.length)")
            // Nếu length=3 → "仿佛在" được chọn thay vì "仿佛" → đây là nguyên nhân bug
            if vpAt0.length == 3 {
                print("[Test 3] ⚠️ BUG PATTERN: findLongestMatch trả về length=3 ('仿佛在') thay vì 2 ('仿佛')")
            }
        }

        // Test này KHÔNG có assertion cứng — chỉ in để quan sát
        XCTAssertTrue(true, "Trace test — xem output ở trên")
    }

    // MARK: - Test 4: Full trace với VP dict thực (hiện tại trong app)

    func test_仿佛_traceWithCurrentDict() async throws {
        // Dùng VP dict HIỆN TẠI đang load trong app (không overwrite)
        // → phản ánh đúng hành vi thực tế

        // Đảm bảo translation enabled
        UserDefaults.standard.set(true, forKey: "isTranslationEnabled")
        UserDefaults.standard.set(false, forKey: "isTranslationPronounsEnabled")
        UserDefaults.standard.set(false, forKey: "isTranslationLuatNhanEnabled")

        let trace = TranslateUtils.tokenizeWithTrace("仿佛在一瞬间")
        print("\n[Test 4 - Current App Dict]\n\(trace.description)\n")

        let trace2 = TranslateUtils.tokenizeWithTrace("就在诺诺话音刚落时,整个沉寂的校园仿佛在一瞬间活了过来")
        print("\n[Test 4 - Full Sentence]\n\(trace2.description)\n")

        // Ghi nhận VP scan tại position của '仿' trong câu đầy đủ
        let fanPos = trace2.vpScanLog.first(where: { $0.char == "仿" })
        if let s = fanPos {
            print("[Test 4] VP scan tại '仿': checkText='\(s.checkTextPrefix)' longestVPLen=\(s.longestVPLen)")
            if s.skippedDueToLimit {
                print("[Test 4] 🔴 SKIPPED do limit=\(s.limit)<2 — nextNameStart=\(s.nextNameStart)")
            } else if s.longestVPLen < 2 {
                print("[Test 4] 🔴 longestVPLen<2 — 仿佛 KHÔNG có trong VP dict đang load")
            } else if s.longestVPLen > 2 {
                print("[Test 4] ⚠️ longestVPLen=\(s.longestVPLen) — match DÀI HƠN 仿佛, có thể gây conflict")
            } else {
                print("[Test 4] ✅ longestVPLen=2 — 仿佛 được scan đúng")
            }
        }

        // Test không có assertion cứng — xem output để chẩn đoán
        XCTAssertTrue(true, "Trace test — xem console output để debug")
    }

    // MARK: - Test 5: Regression — các VP 2 ký tự khác không bị ảnh hưởng

    func test_otherVPs_notAffected() async throws {
        try await loadVietPhrase("""
        按下=nhấn xuống
        一瞬间=nháy mắt
        世界=thế giới
        仿佛=phảng phất
        静音=yên lặng/tắt tiếng
        """)

        let trace = TranslateUtils.tokenizeWithTrace("世界按下静音")
        print("\n[Test 5 - Other VPs]\n\(trace.description)\n")

        // Các VP khác phải đúng
        XCTAssertTrue(trace.finalTokens.contains("世界"), "世界 phải là 1 token")
        XCTAssertTrue(trace.finalTokens.contains("按下"), "按下 phải là 1 token")
        XCTAssertTrue(trace.finalTokens.contains("静音"), "静音 phải là 1 token")
    }
}
