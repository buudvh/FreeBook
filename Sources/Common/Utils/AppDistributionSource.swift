import Foundation

/// Nguồn cập nhật app cho LiveContainer (định dạng nguồn AltStore).
///
/// CI (`build-ipa.yml` → `Scripts/ci/publish_altstore_source.py`) ghi `apps.json` lên nhánh `source` của repo sau mỗi
/// lần build thành công trên `main`: mỗi bản là một GitHub Release `build-<số build>`, giữ 5 bản mới nhất. Trong
/// LiveContainer: tab Sources › Refresh › Install để lên bản mới.
public enum AppDistributionSource {
    /// URL file nguồn — cố định, không đổi theo bản.
    public static let sourceURLString = "https://raw.githubusercontent.com/buudvh/FreeBook/source/apps.json"

    /// Link sâu của LiveContainer: chuyển sang tab Sources và thêm nguồn (`livecontainer://source?url=…`).
    public static var liveContainerAddSourceURL: URL? {
        var components = URLComponents()
        components.scheme = "livecontainer"
        components.host = "source"
        components.queryItems = [URLQueryItem(name: "url", value: sourceURLString)]
        return components.url
    }
}
