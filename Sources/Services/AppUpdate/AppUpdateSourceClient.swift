import Foundation

/// Đọc bản mới nhất từ nguồn cập nhật LiveContainer (định dạng nguồn AltStore) mà CI ghi sau mỗi lần build xanh
/// (`Scripts/ci/publish_altstore_source.py`). Chỉ lấy `apps[0].versions[0]` — script xếp bản mới nhất lên đầu.
///
/// Đọc qua **API Contents của GitHub** trước (`Accept: application/vnd.github.raw+json` ⇒ trả thẳng nội dung file, cùng
/// định dạng): link `raw.githubusercontent.com` đi qua CDN giữ bản sao tới 300 s (`max-age=300`, thêm tham số vào link
/// không lách được), nên vừa đăng bản mới mà bấm kiểm vẫn nhận danh sách cũ; API chỉ đệm tối đa 60 s. API giới hạn 60
/// lượt/giờ mỗi IP khi không đăng nhập — app chỉ đọc lúc mở app, quay lại sau 30 phút và bấm tay nên dư. API lỗi (hết
/// lượt 403/429, mạng, file hỏng) ⇒ đọc link raw như trước, không bao giờ tệ hơn cách cũ.
enum AppUpdateSourceClient {
    static let apiURL = URL(string: "https://api.github.com/repos/buudvh/FreeBook/contents/apps.json?ref=source")!
    static let rawURL = URL(string: "https://raw.githubusercontent.com/buudvh/FreeBook/source/apps.json")!

    enum FetchError: LocalizedError {
        case badStatus(Int)
        case noVersion

        var errorDescription: String? {
            switch self {
            case .badStatus(let code): return "Nguồn cập nhật trả HTTP \(code)"
            case .noVersion: return "Nguồn cập nhật không có bản nào"
            }
        }
    }

    private struct Source: Decodable {
        let apps: [App]
    }

    private struct App: Decodable {
        let versions: [Version]?
    }

    private struct Version: Decodable {
        let version: String
        let buildVersion: String
        let date: String?
        let localizedDescription: String?
    }

    static func fetchLatest() async throws -> AppUpdateInfo {
        do {
            return try await fetch(from: apiURL, headers: [
                "Accept": "application/vnd.github.raw+json",
                "User-Agent": "TangCongCac"
            ])
        } catch {
            if error is CancellationError { throw error }
            AppLogger.shared.log("⚠️ [AppUpdate] API GitHub lỗi (\(error.localizedDescription)) ⇒ đọc link raw")
            return try await fetch(from: rawURL, headers: [:])
        }
    }

    private static func fetch(from url: URL, headers: [String: String]) async throws -> AppUpdateInfo {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.httpMethod = "GET"
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw FetchError.badStatus(http.statusCode)
        }
        let source = try JSONDecoder().decode(Source.self, from: data)
        guard let latest = source.apps.first?.versions?.first,
              let build = Int(latest.buildVersion.trimmingCharacters(in: .whitespaces)) else {
            throw FetchError.noVersion
        }
        return AppUpdateInfo(
            version: latest.version,
            buildNumber: build,
            date: latest.date.flatMap { ISO8601DateFormatter().date(from: $0) },
            notes: AppUpdateInfo.notes(fromDescription: latest.localizedDescription ?? "")
        )
    }
}
