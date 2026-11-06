import Foundation

/// Quét gói extension (thư mục hoặc gói một file, qua `ExtensionPackageReader`) để tìm **mọi script có hàm
/// `execute`**, không chỉ những khoá khai trong `plugin.json`.
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

    /// Bốn cách khai `execute` mà tiện ích thực tế dùng: `function execute(`,
    /// `async function execute(`, `execute = function`/`execute: function`, và `execute = (`/`execute = async (`.
    private static let executeRegex = try! NSRegularExpression(
        pattern: #"(?:\bfunction\s+execute\s*\()|(?:\bexecute\s*[:=]\s*(?:async\s+)?(?:function\b|\())"#,
        options: []
    )

    /// Path **tương đối** của mọi `.js` có `execute`, sắp xếp để thứ tự ổn định giữa các lượt gọi.
    /// Rỗng khi `localPath` rỗng hoặc gói không đọc được — không throw, vì đây là đường liệt kê
    /// phục vụ UI, không phải cổng kiểm tra.
    public static func executableScripts(at localPath: String) -> [String] {
        guard !localPath.isEmpty else { return [] }
        return ExtensionPackageReader.listFiles(localPath: localPath)
            .filter { isRootOrSrcScript($0) && hasExecute(relativePath: $0, localPath: localPath) }
            .sorted()
    }

    public static func containsExecute(in source: String) -> Bool {
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        return executeRegex.firstMatch(in: source, options: [], range: range) != nil
    }

    /// `x.js` ở gốc hoặc `src/x.js` — hai chỗ duy nhất runtime resolve.
    private static func isRootOrSrcScript(_ relativePath: String) -> Bool {
        guard relativePath.hasSuffix(".js") else { return false }
        let parts = relativePath.split(separator: "/", omittingEmptySubsequences: false)
        return parts.count == 1 || (parts.count == 2 && parts[0] == Substring(ExtensionPackageReader.scriptFolderName))
    }

    private static func hasExecute(relativePath: String, localPath: String) -> Bool {
        guard let data = ExtensionPackageReader.fileData(relativePath: relativePath, localPath: localPath),
              let source = String(data: data.prefix(maxBytesPerFile), encoding: .utf8) else { return false }
        return containsExecute(in: source)
    }
}
