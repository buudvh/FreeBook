import Foundation

/// Polyfill JS cho `Engine` (trình duyệt ẩn/hiện) — vẫn được nạp **cuối cùng**. Nội dung chuyển nguyên văn từ `JSExecutor.swift` (1.3.481).
enum JSEngineBootstrapScript {
    /// Chuỗi JS, `evaluateScript` ngay sau khi khai báo trong `JSExecutor`.
    static let source = """
    var Engine = {
        newBrowser: function() {
            var browserId = "browser_" + Math.random().toString(36).substr(2, 9);
            _nativeBrowserNew(browserId);
            return {
                _id: browserId,
                launch: function(url, timeout) {
                    console.log("🤖 [Engine.Browser] launch(" + url + ")");
                    var html = _nativeBrowserLaunch(this._id, url, timeout || 5000);
                    return Html.parseWithBase(html, url);
                },
                launchAsync: function(url) {
                    console.log("🤖 [Engine.Browser] launchAsync(" + url + ")");
                    _nativeBrowserLaunchAsync(this._id, url);
                },
                html: function(timeout) {
                    if (timeout && timeout > 0) {
                        sleep(timeout);
                    }
                    var html = _nativeBrowserGetHtml(this._id);
                    return Html.parse(html || "");
                },
                close: function() {
                    console.log("🤖 [Engine.Browser] close()");
                    _nativeBrowserClose(this._id);
                },
                setUserAgent: function(ua) {
                    console.log("🤖 [Engine.Browser] setUserAgent(" + ua + ")");
                },
                callJs: function(script, waitTime) {
                    console.log("🤖 [Engine.Browser] callJs()");
                    var result = _nativeBrowserCallJs(this._id, script, waitTime || 0);
                    return result;
                },
                waitUrl: function(urls, timeout) {
                    console.log("🤖 [Engine.Browser] waitUrl()");
                    return _nativeBrowserWaitUrl(this._id, urls, timeout || 5000);
                },
                block: function(patterns) {
                    console.log("🤖 [Engine.Browser] block()");
                    var arr = Array.isArray(patterns) ? patterns : [patterns];
                    _nativeBrowserBlock(this._id, arr);
                },
                urls: function() {
                    return _nativeBrowserGetUrls(this._id);
                },
                getVariable: function(varName) {
                    return this.callJs(varName, 0);
                },
                waitForReady: function(probeScript, timeout, interval, stablePasses) {
                    console.log("🤖 [Engine.Browser] waitForReady()");
                    var jsonStr = _nativeBrowserWaitForReady(
                        this._id,
                        probeScript || "",
                        timeout || 30000,
                        interval || 250,
                        stablePasses || 2
                    );
                    try {
                        return JSON.parse(jsonStr);
                    } catch(e) {
                        return { ready: false, failed: true, reason: "Failed to parse result JSON: " + e.message, timedOut: false, cancelled: false };
                    }
                }
            };
        },
        newVisibleBrowser: function(title) {
            var browserId = "visible_browser_" + Math.random().toString(36).substr(2, 9);
            _nativeBrowserNewVisible(browserId, title || "");
            return {
                _id: browserId,
                launch: function(url, timeout) {
                    console.log("👁️ [Engine.VisibleBrowser] launch(" + url + ")");
                    var html = _nativeBrowserLaunchVisible(this._id, url, timeout || 15000);
                    return Html.parseWithBase(html, url);
                },
                launchAsync: function(url) {
                    console.log("👁️ [Engine.VisibleBrowser] launchAsync(" + url + ")");
                    _nativeBrowserLaunchAsyncVisible(this._id, url);
                },
                html: function(timeout) {
                    if (timeout && timeout > 0) {
                        sleep(timeout);
                    }
                    var html = _nativeBrowserGetHtmlVisible(this._id);
                    return Html.parse(html || "");
                },
                close: function() {
                    console.log("👁️ [Engine.VisibleBrowser] close()");
                    _nativeBrowserCloseVisible(this._id);
                },
                setUserAgent: function(ua) {
                    console.log("👁️ [Engine.VisibleBrowser] setUserAgent(" + ua + ")");
                },
                callJs: function(script, waitTime) {
                    console.log("👁️ [Engine.VisibleBrowser] callJs()");
                    var result = _nativeBrowserCallJsVisible(this._id, script, waitTime || 0);
                    return result;
                },
                waitUrl: function(urls, timeout) {
                    console.log("👁️ [Engine.VisibleBrowser] waitUrl()");
                    return _nativeBrowserWaitUrlVisible(this._id, urls, timeout || 15000);
                },
                block: function(patterns) {
                    console.log("👁️ [Engine.VisibleBrowser] block()");
                    var arr = Array.isArray(patterns) ? patterns : [patterns];
                    _nativeBrowserBlockVisible(this._id, arr);
                },
                urls: function() {
                    return _nativeBrowserGetUrlsVisible(this._id);
                },
                getVariable: function(varName) {
                    return this.callJs(varName, 0);
                },
                waitForReady: function(probeScript, timeout, interval, stablePasses) {
                    console.log("👁️ [Engine.VisibleBrowser] waitForReady()");
                    var jsonStr = _nativeBrowserWaitForReadyVisible(
                        this._id,
                        probeScript || "",
                        timeout || 30000,
                        interval || 250,
                        stablePasses || 2
                    );
                    try {
                        return JSON.parse(jsonStr);
                    } catch(e) {
                        return { ready: false, failed: true, reason: "Failed to parse result JSON: " + e.message, timedOut: false, cancelled: false };
                    }
                }
            };
        }
    };
    """
}
