import Foundation

/// Đường dẫn tương đối với một thư mục gốc, cho các lượt đo phân loại của màn Dung lượng / Dọn rác.
///
/// - So theo **ranh giới thư mục** (`isSameOrInside`), không so tiền tố chuỗi trần: `TTS/VieNeu` là tiền tố chuỗi của
///   `TTS/VieNeuTurbo` nhưng không phải thư mục cha của nó.
/// - iOS có lúc trả đường dẫn kèm `/private` (`/private/var/…`, nhất là `temporaryDirectory`), lúc không (bài học 1.3.642
///   ở `LocalMediaImportWorkspace`) ⇒ gốc giữ cả hai biến thể, đường dẫn nào khớp biến thể nào cũng được.
/// - Chỉ để **phân loại / đếm**. Kiểm an toàn trước khi xoá thì dùng `JunkPaths.isSafelyInside` (giải symlink).
struct StorageRelativePath: Sendable {
    private let variants: [String]

    init(root: URL) {
        var path = root.standardizedFileURL.path
        while path.count > 1 && path.hasSuffix("/") { path.removeLast() }
        if path.hasPrefix("/private/") {
            variants = [path, String(path.dropFirst("/private".count))]
        } else {
            variants = [path, "/private" + path]
        }
    }

    /// Đường dẫn tương đối của `url` (không có "/" đầu; "" = chính gốc); `nil` = nằm ngoài gốc.
    func relative(_ url: URL) -> String? {
        relative(path: url.path)
    }

    func relative(path: String) -> String? {
        for variant in variants {
            if path == variant { return "" }
            if path.hasPrefix(variant + "/") {
                return String(path.dropFirst(variant.count + 1))
            }
        }
        return nil
    }

    /// `relative` là `root` hoặc nằm trong `root` (cả hai đều tương đối với cùng một gốc).
    static func isSameOrInside(_ relative: String, _ root: String) -> Bool {
        root.isEmpty || relative == root || relative.hasPrefix(root + "/")
    }

    /// `relative` là thư mục cha (xa hay gần) của `descendant`.
    static func isAncestor(_ relative: String, of descendant: String) -> Bool {
        relative.isEmpty ? !descendant.isEmpty : descendant.hasPrefix(relative + "/")
    }

    /// Thư mục / file nông nhất chứa `relative` mà không phải cha của gốc đã biết nào — đơn vị gom của các dòng log / dòng
    /// cháu "không rõ chủ" (vd `Library/Application Support/ai_memory`, `Library/Preferences`, `TTS/VieNeu/foo`).
    static func groupingRoot(of relative: String, knownRoots: [String]) -> String {
        var prefix = ""
        for component in relative.split(separator: "/") {
            prefix = prefix.isEmpty ? String(component) : prefix + "/" + component
            if !knownRoots.contains(where: { isAncestor(prefix, of: $0) }) {
                return prefix
            }
        }
        return relative
    }
}
