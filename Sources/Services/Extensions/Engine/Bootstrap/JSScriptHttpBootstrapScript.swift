import Foundation

/// Polyfill JS cho `Script`/`Http` (VBook). Nội dung chuyển nguyên văn từ `JSExecutor.swift` (1.3.481).
enum JSScriptHttpBootstrapScript {
    /// Chuỗi JS, `evaluateScript` ngay sau khi khai báo trong `JSExecutor`.
    static let source = """
    var Script = {
        execute: function(scriptOrName, functionName) {
            var args = Array.prototype.slice.call(arguments, 2);
            try {
                var isFile = false;
                if (typeof scriptOrName === 'string') {
                    var trimmed = scriptOrName.trim();
                    if (trimmed.endsWith(".js") || (!trimmed.includes(";") && !trimmed.includes("\\n") && !trimmed.includes("{") && !trimmed.includes(" "))) {
                        if (typeof load === 'function') {
                            load(trimmed.endsWith(".js") ? trimmed : (trimmed + ".js"));
                            isFile = true;
                        }
                    }
                }
                if (!isFile) {
                    eval(scriptOrName);
                }
                var fn = eval(functionName);
                if (typeof fn === 'function') {
                    return fn.apply(null, args);
                } else {
                    throw new Error("Function '" + functionName + "' is not defined or not a function.");
                }
            } catch (e) {
                console.log("❌ Script.execute error: " + e.message);
                throw e;
            }
        }
    };

    var Http = {
        _request: function(method, url) {
            var req = {
                _url: url,
                _method: method || "GET",
                _headers: {},
                _params: {},
                _body: null,

                header: function(key, value) {
                    this._headers[key] = value;
                    return this;
                },

                headers: function(dict) {
                    if (dict) {
                        for (var key in dict) {
                            this._headers[key] = dict[key];
                        }
                    }
                    return this;
                },

                param: function(key, value) {
                    this._params[key] = value;
                    return this;
                },

                params: function(dict) {
                    if (dict) {
                        for (var key in dict) {
                            this._params[key] = dict[key];
                        }
                    }
                    return this;
                },

                body: function(content) {
                    this._body = content;
                    return this;
                },

                contentType: function(type) {
                    this._headers["Content-Type"] = type;
                    return this;
                },

                _execute: function() {
                    var finalUrl = this._url;
                    var paramKeys = Object.keys(this._params);
                    if (paramKeys.length > 0) {
                        var queryString = paramKeys.map(function(key) {
                            var val = req._params[key];
                            return encodeURIComponent(key) + "=" + encodeURIComponent(val !== null && val !== undefined ? val : "");
                        }).join("&");

                        if (this._method.toUpperCase() === "GET") {
                            finalUrl += (finalUrl.indexOf("?") >= 0 ? "&" : "?") + queryString;
                        } else if (!this._body) {
                            this._body = queryString;
                            if (!this._headers["Content-Type"]) {
                                this._headers["Content-Type"] = "application/x-www-form-urlencoded";
                            }
                        }
                    }

                    var options = {
                        method: this._method,
                        headers: this._headers,
                        body: this._body
                    };

                    return fetch(finalUrl, options);
                },

                html: function(encoding) {
                    return this._execute().html(encoding);
                },

                string: function(encoding) {
                    return this._execute().text(encoding);
                },

                text: function(encoding) {
                    return this._execute().text(encoding);
                },

                json: function() {
                    return this._execute().json();
                },

                table: function() {
                    return this._execute().json();
                },

                code: function() {
                    return this._execute().status;
                },

                status: function() {
                    return this._execute().status;
                },

                base64: function() {
                    return this._execute().base64();
                },

                headers: function() {
                    return this._execute().headers;
                }
            };
            return req;
        },

        get: function(url) {
            return this._request("GET", url);
        },

        post: function(url) {
            return this._request("POST", url);
        },

        request: function(methodOrUrl, url) {
            if (url !== undefined) {
                return this._request(methodOrUrl, url);
            } else {
                return this._request("GET", methodOrUrl);
            }
        },

        head: function(url) {
            return this._request("HEAD", url);
        },

        put: function(url) {
            return this._request("PUT", url);
        },

        delete: function(url) {
            return this._request("DELETE", url);
        },

        patch: function(url) {
            return this._request("PATCH", url);
        }
    };
    """
}
