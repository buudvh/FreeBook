import Foundation

/// Kết quả đầy đủ của `VideoSourceResolver.resolveSource`: phương án đang phát, nguồn gốc link (cho log chẩn đoán) và
/// các phương án dự phòng khi item phát ra hình mà **không có tiếng** (`VideoPlaybackSession+AudioFallback`).
///
/// Chỉ link do `VideoMediaSniffer` dò từ trang (track `auto`/`webview`) mới có dự phòng: tối đa
/// `maxAlternateCandidates` m3u8 khác đã gom (thứ tự `VideoHLSPlaylistProbe`: master có AUDIO trước), cuối cùng là
/// nhúng trang. Link tiện ích trả thẳng (`native`, hoặc `auto`/`webview` trỏ thẳng file media) không có dự phòng.
///
/// Ngoại lệ có chủ đích so với DOC: DOC nói `auto` không có fallback nhúng — vẫn đúng khi **không dò được link** (báo
/// lỗi như cũ). Nhúng ở đây chỉ là bước cuối của ca dò được link nhưng phát ra mất tiếng.
struct VideoSourceResolution: Sendable {
    enum Origin: Sendable {
        /// URL media do tiện ích trả thẳng.
        case extensionURL
        /// Playlist text / URI `data:` do tiện ích trả.
        case extensionPlaylist
        /// Link `VideoMediaSniffer` dò từ trang xem/embed.
        case sniffed
        /// Nhúng trang vào WKWebView.
        case embed

        var label: String {
            switch self {
            case .extensionURL: return "link tiện ích trả thẳng (native)"
            case .extensionPlaylist: return "playlist text của tiện ích (hlsText)"
            case .sniffed: return "dò link từ trang"
            case .embed: return "nhúng trang"
            }
        }
    }

    struct Attempt: Sendable {
        let plan: VideoPlaybackPlan
        let origin: Origin
        /// Ứng viên cụ thể khi dò link (`m3u8 #2 media`) — không chứa URL.
        let note: String?
    }

    /// Số m3u8 dự phòng tối đa trước khi nhúng trang: mỗi lượt thử tốn vài giây nạp + kiểm tiếng.
    static let maxAlternateCandidates = 3

    private(set) var current: Attempt
    private(set) var fallbacks: [Attempt]
    /// Tóm tắt lượt phân loại playlist của `VideoHLSPlaylistProbe` — không chứa URL.
    let playlistSummary: String?
    /// Thứ tự phương án đang phát, tính từ 1 (1 = link chính).
    private(set) var attemptNumber = 1
    let totalAttempts: Int

    init(current: Attempt, fallbacks: [Attempt], playlistSummary: String?) {
        self.current = current
        self.fallbacks = fallbacks
        self.playlistSummary = playlistSummary
        self.totalAttempts = fallbacks.count + 1
    }

    /// Link tiện ích trả thẳng hoặc nhúng trang: không có dự phòng.
    init(direct plan: VideoPlaybackPlan) {
        let origin: Origin
        switch plan {
        case .native: origin = .extensionURL
        case .hlsText: origin = .extensionPlaylist
        case .embed: origin = .embed
        }
        self.init(current: Attempt(plan: plan, origin: origin, note: nil), fallbacks: [], playlistSummary: nil)
    }

    var isOnFallback: Bool { attemptNumber > 1 }

    /// Chuyển sang phương án kế; hết thì trả `nil` và giữ nguyên.
    mutating func advance() -> Attempt? {
        guard !fallbacks.isEmpty else { return nil }
        current = fallbacks.removeFirst()
        attemptNumber += 1
        return current
    }

    /// Mô tả nguồn của phương án đang phát cho log: nguồn gốc, ứng viên, số thứ tự, loại playlist — không có URL đầy đủ.
    var diagnostics: String {
        var parts = ["nguồn: \(current.origin.label)" + (current.note.map { " [\($0)]" } ?? "")]
        parts.append("phương án \(attemptNumber)/\(totalAttempts)")
        if case .hlsText(let playlist, let baseURL, _) = current.plan {
            parts.append("playlist text: \(VideoHLSPlaylistProbe.label(ofPlaylist: playlist)), base \(baseURL?.host ?? "-")")
        }
        if let playlistSummary {
            parts.append("playlist: \(playlistSummary)")
        }
        return parts.joined(separator: ", ")
    }

    // MARK: - Che URL cho log

    /// `scheme://host/…/tên-file-cuối` — không bao giờ có query/fragment (thường chứa token). URL không có host
    /// (`blob:`, `data:`…) chỉ ghi scheme và tên cuối (cắt ngắn); `data:` chỉ ghi scheme.
    static func redact(_ url: URL) -> String {
        let scheme = url.scheme?.lowercased() ?? "?"
        guard scheme != "data" else { return "data:…" }
        let last = String(url.lastPathComponent.prefix(80))
        guard let host = url.host, !host.isEmpty else { return "\(scheme):…/\(last)" }
        return "\(scheme)://\(host)/…/\(last == "/" ? "" : last)"
    }

    /// Như `redact(_ url:)` cho chuỗi URL thô (URI trong error log của `AVPlayerItem`).
    static func redact(_ text: String) -> String {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return "chuỗi không phải URL (\(text.count) ký tự)"
        }
        return redact(url)
    }
}
