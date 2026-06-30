import XCTest
import JavaScriptCore
@testable import FreeBook

final class ParserTests: XCTestCase {
    
    // Kiểm tra Jsoup DOM parser bridge
    func testJSBridgeDOM() throws {
        let executor = JSExecutor()
        
        let script = """
        function testDOM() {
            var doc = Html.parse("<html><body><div id='content'><h1 class='title'>Tiêu Đề Truyện</h1><p>Nội dung chương 1</p></div></body></html>");
            var title = doc.select("h1.title").text();
            var content = doc.select("div#content p").text();
            return title + " - " + content;
        }
        """
        
        executor.context.evaluateScript(script)
        guard let function = executor.context.objectForKeyedSubscript("testDOM") else {
            XCTFail("testDOM function not found")
            return
        }
        
        let result = function.call(withArguments: [])
        XCTAssertEqual(result?.toString(), "Tiêu Đề Truyện - Nội dung chương 1")
    }
    
    // Kiểm tra khả năng xử lý Promise/Async-Await của JSExecutor
    func testJSBridgePromise() async throws {
        let executor = JSExecutor()
        
        let script = """
        function testPromise() {
            return Promise.resolve("Promise resolved successfully!");
        }
        """
        
        do {
            let result = try await executor.runAsync(scriptContent: script, functionName: "testPromise", arguments: [])
            XCTAssertEqual(result.toString(), "Promise resolved successfully!")
        } catch {
            XCTFail("Promise test failed with error: \(error.localizedDescription)")
        }
    
    // Kiểm tra tính năng inject biến config toàn cục
    func testJSBridgeConfig() throws {
        let executor = JSExecutor()
        
        let configs = [
            "BASE_URL": "https://www.sudugu.org",
            "REMOVE_TEXT": "求月票",
            "MAX_CHAPTERS": 100
        ] as [String : Any]
        
        executor.injectGlobals(configs)
        
        let script = """
        function checkConfig() {
            return BASE_URL + " | " + REMOVE_TEXT + " | " + MAX_CHAPTERS;
        }
        """
        
        executor.context.evaluateScript(script)
        guard let function = executor.context.objectForKeyedSubscript("checkConfig") else {
            XCTFail("checkConfig function not found")
            return
        }
        
        let result = function.call(withArguments: [])
    }
    
    // Kiểm tra tính năng load("libs.js") tương thích Rhino
    func testJSBridgeLoadLibrary() throws {
        // Tạo thư mục tạm và file libs.js
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        let libUrl = tempDir.appendingPathComponent("libs.js")
        let libCode = "function helper() { return 'LoadedFromLibs'; }"
        try! libCode.write(to: libUrl, atomically: true, encoding: .utf8)
        
        // Khởi chạy executor trỏ tới thư mục tạm
        let executor = JSExecutor(localPath: tempDir.path)
        
        let script = """
        load("libs.js");
        function testLoad() {
            return helper();
        }
        """
        
        executor.context.evaluateScript(script)
        guard let function = executor.context.objectForKeyedSubscript("testLoad") else {
            XCTFail("testLoad function not found")
            return
        }
        
        let result = function.call(withArguments: [])
        XCTAssertEqual(result?.toString(), "LoadedFromLibs")
        
        // Dọn dẹp
        try? FileManager.default.removeItem(at: tempDir)
    }
}
