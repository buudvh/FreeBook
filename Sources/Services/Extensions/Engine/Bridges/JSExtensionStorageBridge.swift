import Foundation

/// Cầu nối lưu trữ của extension (`localStorage`, `cacheStorage`, `localConfig`, `localCookie`). Hiện chỉ giữ
/// polyfill JS; block `_nativeStorage*` vẫn cài trong `JSExecutor`. Nội dung chuyển nguyên văn từ `JSExecutor.swift` (1.3.481).
enum JSExtensionStorageBridge {
    /// Chuỗi JS dựng các API lưu trữ.
    static let bootstrap = """
    var localStorage = {
        getItem: function(key) {
            var val = _nativeStorageGet(String(key));
            return val !== "" ? val : null;
        },
        setItem: function(key, val) {
            _nativeStorageSet(String(key), String(val !== null && val !== undefined ? val : ""));
        },
        removeItem: function(key) {
            _nativeStorageRemove(String(key));
        },
        clear: function() {
            _nativeStorageClear();
        }
    };

    var __cacheStorageData = {};
    var cacheStorage = {
        getItem: function(key) {
            return __cacheStorageData.hasOwnProperty(key) ? __cacheStorageData[key] : null;
        },
        setItem: function(key, val) {
            __cacheStorageData[key] = String(val !== null && val !== undefined ? val : "");
        },
        removeItem: function(key) {
            delete __cacheStorageData[key];
        },
        clear: function() {
            __cacheStorageData = {};
        }
    };

    var localConfig = {
        getItem: function(key) {
            if (typeof _injectedConfigs !== 'undefined' && _injectedConfigs && _injectedConfigs.hasOwnProperty(key)) {
                return _injectedConfigs[key];
            }
            if (typeof this[key] !== 'undefined') {
                return this[key];
            }
            return null;
        },
        get: function(key) {
            return this.getItem(key);
        }
    };

    var __cookieData = "";
    var localCookie = {
        setCookie: function(cookieStr) {
            __cookieData = String(cookieStr || "");
        },
        getCookie: function(url) {
            return __cookieData;
        }
    };
    """
}
