import Foundation

/// Quét thư mục extension để tìm **mọi script có hàm `execute`**, không chỉ những khoá khai trong
/// `plugin.json`.
///
/// Vì sao cần: `scriptKeys` chỉ có những gì extension **khai** ở mục `script`. Nhưng script phụ do
/// `home`/`genre` trả về — và script tác giả đang viết dở — không nằm trong đó, nên màn debug không có
/// cách nào liệt kê chúng ra; người dùng phải tự gõ tên file vào đường `custom`. Quét thư mục cho ra
/// đúng tập file *chạy được*, để client hiện thành lựa chọn entrypoint.
///
/// Chỉ quét **gốc extension** và **`src/`**, đúng thứ tự resolve của production
/// (`ExtensionDraftValidator.resolvedScriptPath` và `ExtensionManager.executeCustomScript`). Không đệ
/// quy sâu hơn: file nằm ngoài hai chỗ đó thì runtime cũng không resolve được, liệt kê ra là hứa một
/// việc không chạy.
public enum ExtensionDebugScriptScanner {
    /// Chỉ đọc `maxBytesPerFile` đầu mỗi file: `execute` luôn khai ở top level, và một file JS bệnh lý
    /// vài MB không được phép làm `extensions.list` treo.
    private static let maxBytesPerFile = 256 * 1024

    /// Bốn cách khai `execute` mà extension VBook thực tế dùng: `function execute(`,
    /// `async function execute(`, `execute = function`/`execute: function`, và `execute = (`/`execute = async (`.
    private static let executeRegex = try! NSRegularExpression(
        pattern: #"(?:\bfunction\s+execute\s*\()|(?:\bexecute\s*[:=]\s*(?:async\s+)?(?:function\b|\())"#,
        options: []
    )

    /// Path **tương đối** của mọi `.js` có `execute`, sắp xếp để thứ tự ổn định giữa các lượt gọi.
    /// Rỗng khi `localPath` rỗng hoặc thư mục không đọc được — không throw, vì đây là đường liệt kê
    /// phục vụ UI, không phải cổng kiểm tra.
    public static func executableScripts(at localPath: String) -> [String] {
        guard !localPath.isEmpty else { return [] }
        let root = URL(fileURLWithPath: localPath)
        var found: [String] = []

        for folder in ["", "src"] {
            let directory = folder.isEmpty ? root : root.appendingPathComponent(folder)
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { continue }
            for name in names where name.hasSuffix(".js") {
                guard hasExecute(at: directory.appendingPathComponent(name)) else { continue }
                found.append(folder.isEmpty ? name : "\(folder)/\(name)")
            }
        }

        return found.sorted()
    }

    private static func hasExecute(at fileUrl: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: fileUrl) else { return false }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: maxBytesPerFile),
              let source = String(data: data, encoding: .utf8) else { return false }
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        return executeRegex.firstMatch(in: source, options: [], range: range) != nil
    }
}
