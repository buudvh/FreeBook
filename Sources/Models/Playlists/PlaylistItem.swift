import Foundation

/// Một mục của playlist = **một bài** (album âm thanh) hoặc **một tập** (phim) — không phải cả album/phim.
///
/// Mục giữ đủ để phát lại mà không cần `Book` trên máy: tiện ích (`packageId`), link album/phim (`detailUrl`, nguyên văn
/// như item tiện ích trả về), chỉ số bài/tập trong mục lục (`index` — chỉ số **thưa** của mục lục đủ, dòng `section` chiếm
/// số, đúng `AudioPlaybackSession.Track.index` / `VideoPlaybackSession.Episode.index`) và link bài/tập (`chapterUrl`).
/// `host` / `sourceName` (tuỳ chọn) để dựng lại `AudioListenRequest` / `VideoWatchRequest` và làm `Referer` khi tải bìa.
///
/// Giải mã **khoan dung** (`init(from:)`): trường nào vắng thì lấy mặc định — file cũ thiếu trường mới vẫn đọc được.
struct PlaylistItem: Codable, Identifiable, Equatable, Hashable, Sendable {
    let id: UUID
    let packageId: String
    let detailUrl: String
    let index: Int
    let chapterUrl: String
    /// Tên bài / tập (rỗng ⇒ hiện "Bài N" / "Tập N").
    let title: String
    /// Dòng phụ: nghệ sĩ (nhạc) hoặc tên phim (video).
    let subtitle: String
    let coverUrl: String
    /// Tên album / phim chứa mục này.
    let albumTitle: String
    let host: String?
    let sourceName: String?
    let addedAt: Date

    init(
        id: UUID = UUID(),
        packageId: String,
        detailUrl: String,
        index: Int,
        chapterUrl: String,
        title: String,
        subtitle: String,
        coverUrl: String,
        albumTitle: String,
        host: String? = nil,
        sourceName: String? = nil,
        addedAt: Date = Date()
    ) {
        self.id = id
        self.packageId = packageId
        self.detailUrl = detailUrl
        self.index = index
        self.chapterUrl = chapterUrl
        self.title = title
        self.subtitle = subtitle
        self.coverUrl = coverUrl
        self.albumTitle = albumTitle
        self.host = host
        self.sourceName = sourceName
        self.addedAt = addedAt
    }

    /// Khoá chống trùng trong **một** playlist: tiện ích + link bài/tập; link rỗng ⇒ tiện ích + link album/phim + chỉ số.
    var dedupeKey: String {
        let chapter = chapterUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        if !chapter.isEmpty {
            return "\(packageId)|chapter|\(chapter)"
        }
        return "\(packageId)|detail|\(detailUrl.trimmingCharacters(in: .whitespacesAndNewlines))|\(index)"
    }

    /// Tên hiện trên hàng: tên bài/tập, rỗng thì "Bài N" / "Tập N" như trình nghe / màn xem.
    func displayTitle(kind: PlaylistKind) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty else { return trimmed }
        return kind == .audio ? "Bài \(index + 1)" : "Tập \(index + 1)"
    }

    /// `Referer` khi tải bìa: host của album, không có thì link album (loader tự chuẩn hoá về origin).
    var coverReferer: String? {
        if let host, !host.isEmpty { return host }
        return detailUrl.isEmpty ? nil : detailUrl
    }

    private enum CodingKeys: String, CodingKey {
        case id, packageId, detailUrl, index, chapterUrl, title, subtitle, coverUrl, albumTitle, host, sourceName, addedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        packageId = try container.decodeIfPresent(String.self, forKey: .packageId) ?? ""
        detailUrl = try container.decodeIfPresent(String.self, forKey: .detailUrl) ?? ""
        index = try container.decodeIfPresent(Int.self, forKey: .index) ?? 0
        chapterUrl = try container.decodeIfPresent(String.self, forKey: .chapterUrl) ?? ""
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle) ?? ""
        coverUrl = try container.decodeIfPresent(String.self, forKey: .coverUrl) ?? ""
        albumTitle = try container.decodeIfPresent(String.self, forKey: .albumTitle) ?? ""
        host = try container.decodeIfPresent(String.self, forKey: .host)
        sourceName = try container.decodeIfPresent(String.self, forKey: .sourceName)
        addedAt = try container.decodeIfPresent(Date.self, forKey: .addedAt) ?? Date()
    }
}
