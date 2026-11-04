import JavaScriptCore

/// Năm đối tượng chuẩn của môi trường JS (`java`, `source`, `cookie`, `cache`, `infoMap`, spec §6.2) được gán lại trước
/// **mỗi** lần chạy. Rule chạy bằng eval gián tiếp ở phạm vi toàn cục, nên `cookie=cookie.getKey(…)` không khai báo (晋江
/// chapterUrl, 天地中文网 header) thay `cookie` bằng một chuỗi cho mọi script sau ⇒ `cookie.getKey is not a function` từ
/// chương thứ hai. Bản Android chạy mỗi lần trong phạm vi riêng nên không rò. Không đặt chỉ-đọc: chính script đó còn đọc
/// lại giá trị nó vừa gán (`'&token='+cookie`).
extension LegadoJSRuntime {
    /// Tên các đối tượng chuẩn; lần chạy lồng lưu và trả lại cả chúng (lần ngoài có thể đang giữ giá trị tự gán).
    static let standardObjectNames = ["java", "source", "cookie", "cache", "infoMap"]

    /// Gọi một lần sau bootstrap: chụp năm đối tượng vào bao đóng của hàm ẩn `__lgRestoreStd`.
    func installStandardObjectRestore() {
        let names = Self.standardObjectNames.map { "'\($0)'" }.joined(separator: ", ")
        context.evaluateScript("""
        (function (g) {
          var names = [\(names)], saved = {};
          names.forEach(function (k) { saved[k] = g[k]; });
          Object.defineProperty(g, '__lgRestoreStd', { value: function () {
            names.forEach(function (k) { if (g[k] !== saved[k]) { g[k] = saved[k]; } });
          } });
        })(this);
        """)
    }

    /// Trả năm đối tượng chuẩn về bản gốc (trước mỗi lần chạy, trong `apply`).
    func restoreStandardObjects() {
        _ = callHelper("__lgRestoreStd", "")
    }
}
