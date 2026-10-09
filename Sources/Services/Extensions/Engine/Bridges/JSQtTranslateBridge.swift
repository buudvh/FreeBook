import Foundation

/// Cầu nối `Qt.translate` (Quick Translator) cho extension. Hiện chỉ giữ polyfill JS; block `_nativeQtTranslate`
/// vẫn cài trong `JSExecutor`. Nội dung chuyển nguyên văn từ `JSExecutor.swift` (1.3.481).
enum JSQtTranslateBridge {
    /// Chuỗi JS dựng `Qt`.
    static let bootstrap = """
    var Qt = {
        translate: function(text, to, extras) {
            return _nativeQtTranslate(text || "", to || "vi", extras || null);
        },
        atob: function(s) { return atob(s); },
        btoa: function(s) { return btoa(s); },
        md5: function(s) { return typeof Crypto !== 'undefined' && Crypto.md5 ? Crypto.md5(s) : s; },
        sha256: function(s) { return typeof Crypto !== 'undefined' && Crypto.sha256 ? Crypto.sha256(s) : s; },
        sha1: function(s) { return typeof Crypto !== 'undefined' && Crypto.sha1 ? Crypto.sha1(s) : s; },
        sha512: function(s) { return typeof Crypto !== 'undefined' && Crypto.sha512 ? Crypto.sha512(s) : s; },
        formatDate: function(date, format) { return date ? (typeof date === 'object' && date.toISOString ? date.toISOString().split('T')[0] : date.toString()) : ""; },
        formatDateTime: function(date, format) { return date ? (typeof date === 'object' && date.toISOString ? date.toISOString() : date.toString()) : ""; },
        formatTime: function(date, format) { return date ? (typeof date === 'object' && date.toTimeString ? date.toTimeString() : date.toString()) : ""; },
        include: function(file) { if (typeof load === 'function') load(file); },
        resolvedUrl: function(url) { return url; },
        openUrlExternally: function(url) { return true; },
        platform: { os: "ios" },
        point: function(x, y) { return { x: x || 0, y: y || 0 }; },
        size: function(w, h) { return { width: w || 0, height: h || 0 }; },
        rect: function(x, y, w, h) { return { x: x || 0, y: y || 0, width: w || 0, height: h || 0 }; },
        rgba: function(r, g, b, a) { return "rgba(" + Math.round(r*255) + "," + Math.round(g*255) + "," + Math.round(b*255) + "," + (a !== undefined ? a : 1) + ")"; },
        hsla: function(h, s, l, a) { return "hsla(" + Math.round(h*360) + "," + Math.round(s*100) + "%," + Math.round(l*100) + "%," + (a !== undefined ? a : 1) + ")"; },
        quit: function() {},
        exit: function() {}
    };
    """
}
