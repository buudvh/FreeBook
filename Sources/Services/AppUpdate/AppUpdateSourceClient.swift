import Foundation

/// Đọc bản mới nhất từ nguồn cập nhật LiveContainer (định dạng nguồn AltStore) mà CI ghi sau mỗi lần build xanh
/// (`Scripts/ci/publish_altstore_source.py`). Chỉ lấy `apps[0].versions[0]` — script xếp bản mới nhất lên đầu.
enum AppUpdateSourceClient {
    static let sourceURL = URL(string: "https://raw.githubusercontent.com/buudvh/FreeBook/source/apps.json")!

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
        var request = URLRequest(url: sourceURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.httpMethod = "GET"
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
