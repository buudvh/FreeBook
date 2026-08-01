import XCTest
import JavaScriptCore
@testable import FreeBook

final class EngineBootstrapTests: XCTestCase {
    func testJSBridgeEngineGlobalsAndReservedKeysProtection() async throws {
        let executor = JSExecutor()
        
        // 1. Verify Engine.newBrowser and Engine.newVisibleBrowser both exist as functions on Engine
        let testScript = """
        function checkEngineFunctions() {
            var browserType = (typeof Engine !== "undefined" && Engine !== null) ? typeof Engine.newBrowser : "undefined";
            var visibleType = (typeof Engine !== "undefined" && Engine !== null) ? typeof Engine.newVisibleBrowser : "undefined";
            return browserType + "," + visibleType;
        }
        """
        let funcRes = try await executor.runAsync(scriptContent: testScript, functionName: "checkEngineFunctions", arguments: [])
        XCTAssertEqual(funcRes.toString(), "function,function", "Both newBrowser and newVisibleBrowser must be functions on Engine")
        
        // 2. Snapshot initial typeof state of all 12 reserved globals before injection
        let snapshotScript = """
        function snapshotReservedGlobals() {
            var keys = ["Engine", "Response", "Html", "Script", "Http", "Crypto", "console", "Console", "fetch", "load", "atob", "btoa"];
            var snap = {};
            for (var i = 0; i < keys.length; i++) {
                var k = keys[i];
                snap[k] = typeof this[k];
            }
            return JSON.stringify(snap);
        }
        """
        let snapRes = try await executor.runAsync(scriptContent: snapshotScript, functionName: "snapshotReservedGlobals", arguments: [])
        let initialSnapJson = snapRes.toString() ?? "{}"
        
        // 3. Attempt to inject overwrite values for all 12 reserved keys AND ordinary config keys like BASE_URL
        let injectionPayload: [String: Any] = [
            "Engine": "OVERWRITTEN_ENGINE",
            "Response": "OVERWRITTEN_RESPONSE",
            "Html": "OVERWRITTEN_HTML",
            "Script": "OVERWRITTEN_SCRIPT",
            "Http": "OVERWRITTEN_HTTP",
            "Crypto": "OVERWRITTEN_CRYPTO",
            "console": "OVERWRITTEN_CONSOLE",
            "Console": "OVERWRITTEN_CONSOLE_UPPER",
            "fetch": "OVERWRITTEN_FETCH",
            "load": "OVERWRITTEN_LOAD",
            "atob": "OVERWRITTEN_ATOB",
            "btoa": "OVERWRITTEN_BTOA",
            "BASE_URL": "https://example.com/api",
            "CUSTOM_CONFIG_KEY": "12345"
        ]
        executor.injectGlobals(injectionPayload)
        
        // 4. Verify that ordinary keys inject correctly and EVERY reserved key remains untouched and un-overwritten
        let verifyScript = """
        function verifyGlobalProtection(initialSnapJson) {
            var initial = JSON.parse(initialSnapJson);
            var keys = ["Engine", "Response", "Html", "Script", "Http", "Crypto", "console", "Console", "fetch", "load", "atob", "btoa"];
            var errors = [];
            for (var i = 0; i < keys.length; i++) {
                var k = keys[i];
                var currentType = typeof this[k];
                if (currentType !== initial[k]) {
                    errors.push(k + " type changed: expected " + initial[k] + " but got " + currentType);
                }
                if (this[k] === "OVERWRITTEN_" + k.toUpperCase() || this[k] === "OVERWRITTEN_CONSOLE_UPPER") {
                    errors.push(k + " was overwritten by injectGlobals");
                }
            }
            
            if (typeof Engine !== "object" || Engine === null) {
                errors.push("Engine is not an object");
            } else {
                if (typeof Engine.newBrowser !== "function") {
                    errors.push("Engine.newBrowser is not a function");
                }
                if (typeof Engine.newVisibleBrowser !== "function") {
                    errors.push("Engine.newVisibleBrowser is not a function");
                }
            }
            
            if (typeof BASE_URL !== "string" || BASE_URL !== "https://example.com/api") {
                errors.push("BASE_URL ordinary config key not injected properly");
            }
            if (typeof CUSTOM_CONFIG_KEY !== "string" || CUSTOM_CONFIG_KEY !== "12345") {
                errors.push("CUSTOM_CONFIG_KEY ordinary config key not injected properly");
            }
            
            if (errors.length > 0) {
                return "FAIL: " + errors.join("; ");
            }
            return "OK";
        }
        """
        let verifyRes = try await executor.runAsync(scriptContent: verifyScript, functionName: "verifyGlobalProtection", arguments: [initialSnapJson])
        XCTAssertEqual(verifyRes.toString(), "OK", "All 12 reserved globals must remain unchanged after attempted injection, and ordinary keys must inject successfully")
    }
}
