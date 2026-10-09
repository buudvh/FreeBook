import Foundation

/// Polyfill JS cho `fetch` — gọi xuống block `_nativeSyncFetch`. Nội dung chuyển nguyên văn từ `JSExecutor.swift` (1.3.481).
enum JSFetchBootstrapScript {
    /// Chuỗi JS, `evaluateScript` ngay sau khi khai báo trong `JSExecutor`.
    static let source = """
    var fetch = function(url, options) {
        var originalUrl = url;
        var originalHeaders = (options && options.headers) ? options.headers : {};

        if (options && options.queries && typeof options.queries === 'object') {
            var qParams = [];
            for (var qKey in options.queries) {
                if (options.queries.hasOwnProperty(qKey)) {
                    var qVal = options.queries[qKey];
                    qParams.push(encodeURIComponent(qKey) + "=" + encodeURIComponent(qVal !== null && qVal !== undefined ? qVal : ""));
                }
            }
            if (qParams.length > 0) {
                var queryString = qParams.join("&");
                if (url.indexOf("?") === -1) {
                    url = url + "?" + queryString;
                } else {
                    if (url.endsWith("?") || url.endsWith("&")) {
                        url = url + queryString;
                    } else {
                        url = url + "&" + queryString;
                    }
                }
            }
        }

        if (options && options.body && typeof options.body === 'object') {
            var params = [];
            for (var key in options.body) {
                if (options.body.hasOwnProperty(key)) {
                    var val = options.body[key];
                    params.push(encodeURIComponent(key) + "=" + encodeURIComponent(val !== null && val !== undefined ? val : ""));
                }
            }
            options.body = params.join("&");
            if (!options.headers) {
                options.headers = {};
            }
            var hasContentType = false;
            for (var h in options.headers) {
                if (h.toLowerCase() === 'content-type') {
                    hasContentType = true;
                    break;
                }
            }
            if (!hasContentType) {
                options.headers["Content-Type"] = "application/x-www-form-urlencoded";
            }
        }

        var res = _nativeSyncFetch(url, options || null);
        var headersMap = res.headers || {};
        var responseObj = {
            ok: res.status >= 200 && res.status < 300,
            status: res.status,
            statusText: res.statusText || (res.status === 200 ? "OK" : "Status " + res.status),
            url: res.url || originalUrl,
            headers: headersMap,
            header: function(name) {
                if (!name) return null;
                var lower = name.toLowerCase();
                for (var k in headersMap) {
                    if (k.toLowerCase() === lower) return headersMap[k];
                }
                return null;
            },
            html: function(encoding) {
                var htmlText = "";
                if (encoding && res.raw) {
                    htmlText = _nativeDecodeBase64(res.raw, encoding);
                } else {
                    htmlText = res.html || "";
                }
                return Html.parseWithBase(htmlText, res.url || originalUrl);
            },
            text: function(encoding) {
                if (encoding && res.raw) {
                    return _nativeDecodeBase64(res.raw, encoding);
                }
                return res.html || "";
            },
            json: function() {
                return JSON.parse(res.html || "{}");
            },
            base64: function() {
                return res.raw || "";
            },
            blob: function() {
                var contentType = this.header("content-type") || "application/octet-stream";
                var rawBase64 = res.raw || "";
                return {
                    size: Math.round(rawBase64.length * 3 / 4),
                    type: contentType,
                    base64: function() { return rawBase64; }
                };
            },
            request: {
                url: originalUrl,
                headers: originalHeaders
            }
        };

        responseObj.headers.get = function(name) {
            return responseObj.header(name);
        };

        return responseObj;
    };
    """
}
