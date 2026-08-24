import Foundation

/// Sinh trang Home dạng HTML nhúng cho trình duyệt bypass.
/// Tách khỏi `BypassWebView` để giữ file view dưới baseline dòng.
enum BypassBrowserHomePage {
    /// Icon dự phòng khi tiện ích không có `icon.png` lẫn `iconUrl`.
    private static let fallbackIconBase64 = "data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHdpZHRoPSIyNCIgaGVpZ2h0PSIyNCIgdmlld0JveD0iMCAwIDI0IDI0IiBmaWxsPSJub25lIiBzdHJva2U9IiMwMDdhZmYiIHN0cm9rZS13aWR0aD0iMiIgc3Ryb2tlLWxpbmVjYXA9InJvdW5kIiBzdHJva2UtbGluZWpvaW49InJvdW5kIj48cGF0aCBkPSJNMjEgMTZWOGEyIDIgMCAwIDAtMS0xLjczbC03LTRhMiAyIDAgMCAwLTIgMGwtNyA0QTIgMiAwIDAgMCAzIDh2OGEyIDIgMCAwIDAgMSAxLjczbDcgNGEyIDIgMCAwIDAgMiAwbDctNGEyIDIgMCAwIDAgMS0xLzczeiI+PC9wYXRoPjwvc3ZnPg=="

    /// - Parameter extensions: các tiện ích đã cài, đang bật và có `sourceUrl`.
    static func html(for extensions: [Extension]) -> String {
        var extsHtml = ""

        for ext in extensions {
            let iconSrc = iconSource(for: ext)
            extsHtml += """
            <a class="card" href="\(ext.sourceUrl)">
                <div class="ext-header">
                    <img class="ext-icon" src="\(iconSrc)" onerror="this.onerror=null; this.src='\(fallbackIconBase64)';"/>
                    <div class="ext-name">\(ext.name)</div>
                </div>
                <div class="ext-url">\(ext.sourceUrl)</div>
            </a>
            """
        }

        let emptyState = "<div style='padding: 16px; text-align: center; color: #8e8e93; font-size: 15px; background: white; border-radius: 12px;'>Chưa có nguồn truyện nào được cài đặt</div>"

        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=no">
            <title>Home</title>
            <style>
        \(styleSheet)
            </style>
        </head>
        <body>
            <h1>Home</h1>

            <div class="section-title">Công cụ Tìm kiếm</div>
            <div class="grid">
                <a class="card" href="https://www.google.com">
                    <div class="card-title">Google</div>
                    <div class="card-subtitle">google.com</div>
                </a>
                <a class="card" href="https://www.bing.com">
                    <div class="card-title">Bing</div>
                    <div class="card-subtitle">bing.com</div>
                </a>
                <a class="card" href="https://www.baidu.com">
                    <div class="card-title">Baidu</div>
                    <div class="card-subtitle">baidu.com</div>
                </a>
            </div>

            <div class="section-title">Tiện ích đã cài đặt</div>
            <div class="list">
                \(extsHtml.isEmpty ? emptyState : extsHtml)
            </div>
        </body>
        </html>
        """
    }

    private static func iconSource(for ext: Extension) -> String {
        if !ext.localPath.isEmpty {
            let iconPath = URL(fileURLWithPath: ext.localPath).appendingPathComponent("icon.png").path
            if FileManager.default.fileExists(atPath: iconPath),
               let data = try? Data(contentsOf: URL(fileURLWithPath: iconPath)) {
                return "data:image/png;base64,\(data.base64EncodedString())"
            }
        }
        if let iconUrl = ext.iconUrl, !iconUrl.isEmpty {
            return iconUrl
        }
        return fallbackIconBase64
    }

    private static let styleSheet = """
                body {
                    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
                    background-color: #f2f2f7;
                    color: #1c1c1e;
                    margin: 0;
                    padding: 20px;
                }
                h1 {
                    font-size: 24px;
                    font-weight: 700;
                    margin-bottom: 20px;
                    text-align: center;
                }
                .section-title {
                    font-size: 14px;
                    font-weight: 600;
                    text-transform: uppercase;
                    color: #8e8e93;
                    margin-top: 24px;
                    margin-bottom: 10px;
                    padding-left: 5px;
                }
                .grid {
                    display: grid;
                    grid-template-columns: repeat(2, 1fr);
                    gap: 12px;
                }
                .card {
                    background-color: #ffffff;
                    border-radius: 12px;
                    padding: 16px;
                    text-decoration: none;
                    color: inherit;
                    display: flex;
                    flex-direction: column;
                    box-shadow: 0 1px 3px rgba(0,0,0,0.05);
                }
                .card:active {
                    background-color: #e5e5ea;
                }
                .card-title {
                    font-size: 17px;
                    font-weight: 600;
                    color: #007aff;
                    margin-bottom: 4px;
                }
                .card-subtitle {
                    font-size: 13px;
                    color: #8e8e93;
                    word-break: break-all;
                }
                .ext-header {
                    display: flex;
                    align-items: center;
                    gap: 8px;
                    margin-bottom: 6px;
                }
                .ext-icon {
                    width: 24px;
                    height: 24px;
                    border-radius: 5px;
                    object-fit: cover;
                    flex-shrink: 0;
                }
                .ext-name {
                    font-size: 16px;
                    font-weight: 600;
                    color: #1c1c1e;
                    white-space: nowrap;
                    overflow: hidden;
                    text-overflow: ellipsis;
                }
                .ext-url {
                    font-size: 12px;
                    color: #8e8e93;
                    word-break: break-all;
                }
                .list {
                    display: flex;
                    flex-direction: column;
                    gap: 10px;
                    margin-top: 10px;
                }
                .list .card {
                    flex-direction: column;
                    justify-content: center;
                }
        """
}
