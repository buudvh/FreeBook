import Foundation

/// `metadata` (theo khuôn `plugin.json` của tiện ích) mà một nguồn Legado mang trong kho tiện ích — dựng từ chính
/// nội dung nguồn.
///
/// Nằm ở Models để `ExtensionPackageReader` dựng manifest trong RAM cho file `extensions/legado/<packageId>.json`
/// (nguyên văn `source.json`, không có `plugin.json` đi kèm). Hai hằng `author` / `locale` là nguồn duy nhất:
/// `LegadoSourceIdentity` (Services) trỏ tới đây.
///
/// Không có `version` (nằm ở bản ghi `installed.json`) và `nsfw` (do `ExtensionNsfwClassifier` ở Services tính, mang
/// trong command upsert của `LegadoSourceStore.makeCommand`). Bố cục thư mục cũ còn `plugin.json` tự sinh (có hai trường
/// đó); từ 1.3.756 app không ghi nó nữa.
public enum LegadoSourceManifest {
    /// `metadata.author` của mọi nguồn Legado.
    public static let author = "Legado"
    /// `metadata.locale` ⇒ `Extension.isChineseSource` bật dịch mặc định.
    public static let locale = "zh_CN"

    /// `name`, `author`, `source`, `type`, `locale`, `description`. `nil` với loại không lưu (`unsupported`).
    public static func metadata(source: LegadoBookSource) -> [String: Any]? {
        guard let type = source.kind.extensionType else { return nil }
        return [
            "name": source.bookSourceName,
            "author": author,
            "source": source.bookSourceUrl,
            "type": type,
            "locale": locale,
            "description": source.bookSourceComment
        ]
    }

    /// Bytes JSON ổn định của `{"metadata": …}`; `nil` khi nguồn thuộc loại không lưu.
    public static func manifestData(source: LegadoBookSource) -> Data? {
        guard let metadata = metadata(source: source) else { return nil }
        return LegadoModelJSON.serialize(["metadata": metadata])
    }
}
