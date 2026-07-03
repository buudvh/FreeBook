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
    
    // Kiểm tra hàm atob() và btoa() chuẩn Web
    func testJSBridgeAtobBtoa() throws {
        let executor = JSExecutor()
        
        let script = """
        function testBase64() {
            var raw = "Hello, World!";
            var encoded = btoa(raw);
            var decoded = atob(encoded);
            return encoded + " | " + decoded;
        }
        """
        
        executor.context.evaluateScript(script)
        guard let function = executor.context.objectForKeyedSubscript("testBase64") else {
            XCTFail("testBase64 function not found")
            return
        }
        
        let result = function.call(withArguments: [])
        XCTAssertEqual(result?.toString(), "SGVsbG8sIFdvcmxkIQ== | Hello, World!")
    }
    
    // Kiểm tra các DOM API mới: parseWithBase, outerHtml, hasAttr, absUrl, eachText, eachAttr
    func testJSBridgeDOMNewAPIs() throws {
        let executor = JSExecutor()
        
        let script = """
        function testDOM() {
            var doc = Html.parseWithBase("<html><body><div id='content'><a class='link' href='/relative/path'>Link 1</a><a class='link' href='https://absolute.com/path' target='_blank'>Link 2</a></div></body></html>", "https://example.com/base/");
            
            var div = doc.select("div#content").first();
            var outer = div.outerHtml();
            
            var a1 = doc.select("a").get(0);
            var a2 = doc.select("a").get(1);
            
            var a1HasTarget = a1.hasAttr("target"); // false
            var a2HasTarget = a2.hasAttr("target"); // true
            
            var a1AbsUrl = a1.absUrl("href"); // https://example.com/relative/path (or base-relative resolved)
            var a2AbsUrl = a2.absUrl("href"); // https://absolute.com/path
            
            var texts = doc.select("a").eachText(); // ["Link 1", "Link 2"]
            var targets = doc.select("a").eachAttr("target"); // ["", "_blank"] (or only matching ones depending on implementation)
            
            return outer.indexOf("<div id=\\\"content\\\">") !== -1 + " | " + a1HasTarget + " | " + a2HasTarget + " | " + a1AbsUrl + " | " + a2AbsUrl + " | " + texts.join(",") + " | " + targets.filter(Boolean).join(",");
        }
        """
        
        executor.context.evaluateScript(script)
        guard let function = executor.context.objectForKeyedSubscript("testDOM") else {
            XCTFail("testDOM function not found")
            return
        }
        
        let result = function.call(withArguments: [])
        let resStr = result?.toString() ?? ""
        
        // Kiểm tra xem absUrl có resolve đúng không
        XCTAssertTrue(resStr.contains("https://example.com/relative/path"), "a1 relative path not resolved properly")
        XCTAssertTrue(resStr.contains("https://absolute.com/path"), "a2 absolute path not preserved")
        XCTAssertTrue(resStr.contains("Link 1,Link 2"), "eachText did not return array of texts")
    }
    
    // Kiểm tra các hàm mã hóa của JSCrypto: md5, sha256
    func testJSBridgeCrypto() throws {
        let executor = JSExecutor()
        
        let script = """
        function testCrypto() {
            var raw = "FreeBook";
            var md5Val = Crypto.md5(raw);
            var sha256Val = Crypto.sha256(raw);
            return md5Val + " | " + sha256Val;
        }
        """
        
        executor.context.evaluateScript(script)
        guard let function = executor.context.objectForKeyedSubscript("testCrypto") else {
            XCTFail("testCrypto function not found")
            return
        }
        
        let res = function.call(withArguments: [])
        XCTAssertEqual(res?.toString(), "e8831889c2debe0f8f30b91e9894e637 | db3f920267253a6f1d2b822ad6e729cd41eb4cfb22de97e416a90875e6480838")
    }
    
    // Kiểm tra DOM setters và elements.array()
    func testJSBridgeDOMSetters() throws {
        let executor = JSExecutor()
        
        let script = """
        function testDOMSetters() {
            var doc = Html.parse("<div id='box' class='red'>Text</div>");
            var el = doc.select("#box").first();
            
            // Setters
            el.text("NewText");
            el.addClass("bold");
            el.removeClass("red");
            el.attr("data-id", "123");
            el.append("<span>Appended</span>");
            el.prepend("<span>Prepended</span>");
            
            // Array conversion
            var list = doc.select("span");
            var arr = list.array();
            var texts = arr.map(function(item) { return item.text(); });
            
            return el.text() + " | " + el.className() + " | " + el.attr("data-id") + " | " + texts.join(",");
        }
        """
        
        executor.context.evaluateScript(script)
        guard let function = executor.context.objectForKeyedSubscript("testDOMSetters") else {
            XCTFail("testDOMSetters function not found")
            return
        }
        
        let res = function.call(withArguments: [])
        XCTAssertEqual(res?.toString(), "PrependedNewTextAppended | bold | 123 | Prepended,Appended")
    }
    
    // Kiểm tra Browser flow đồng bộ (async test)
    func testJSBridgeBrowserFlow() async throws {
        let executor = JSExecutor()
        
        let script = """
        function testBrowser() {
            var browser = Engine.newBrowser();
            browser.close();
            return "OK";
        }
        """
        
        do {
            let res = try await executor.runAsync(scriptContent: script, functionName: "testBrowser", arguments: [])
            XCTAssertEqual(res.toString(), "OK")
        } catch {
            XCTFail("Browser test failed: \(error.localizedDescription)")
        }
    }
}
