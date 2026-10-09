import Foundation

/// Polyfill JS lõi nạp vào mọi `JSContext` của `JSExecutor`: `Response` và `UserAgent`.
/// Nội dung chuyển **nguyên văn** từ `JSExecutor.swift` (1.3.481); thứ tự `evaluateScript` vẫn do `JSExecutor` quyết định.
enum JSCoreBootstrapScripts {
    /// `Response.success/error` — nạp đầu tiên.
    static let response = """
    var Response = {
        nextPage: null,
        success: function(data, hasNext) {
            Response.nextPage = hasNext || null;
            return {
                success: true,
                data: data,
                next: hasNext || null
            };
        },
        error: function(message) {
            return {
                success: false,
                message: message || "Lỗi không xác định từ nguồn truyện"
            };
        }
    };

    function __safe_run_extension(functionName, args) {
        try {
            var fn = this[functionName] || eval(functionName);
            if (typeof fn !== 'function') {
                return Response.error("Hàm '" + functionName + "' không tồn tại trong extension");
            }
            var res = fn.apply(null, args);
            if (res === null || res === undefined) {
                return Response.error("Extension không trả về dữ liệu (kết quả là " + (res === null ? "null" : "undefined") + ")");
            }
            return res;
        } catch (e) {
            var msg = e && (e.message || e.toString()) ? (e.message || e.toString()) : "Lỗi thực thi Javascript";
            var line = e && e.line ? " (dòng " + e.line + ")" : "";
            return Response.error(msg + line);
        }
    }
    """

    /// `UserAgent` giả lập trình duyệt.
    static let userAgent = """
    var UserAgent = {
        system: function() { return "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"; },
        android: function() { return "Mozilla/5.0 (Linux; Android 13; SM-S901B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36"; },
        ios: function() { return "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"; },
        pc: function() { return "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"; },
        computer: function() { return "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"; },
        chrome: function() { return "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"; },
        mobile: function() { return "Mozilla/5.0 (Linux; Android 13; SM-S901B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36"; },
        safari: function() { return "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"; },
        firefox: function() { return "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:120.0) Gecko/20100101 Firefox/120.0"; },
        mac: function() { return "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"; },
        macos: function() { return "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"; },
        windows: function() { return "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"; },
        random: function() { return "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"; },
        default: function() { return "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"; },
        get: function() { return "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"; }
    };
    """
}
