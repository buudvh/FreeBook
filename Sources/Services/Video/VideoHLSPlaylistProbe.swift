import Foundation

/// Chọn playlist m3u8 để phát trong các ứng viên mà `VideoMediaSniffer` bắt được ở trang xem.
///
/// Trang xem (ca thật: Dailymotion) request cả playlist gốc (master, có `#EXT-X-STREAM-INF`) lẫn playlist con của
/// từng chất lượng. Playlist con của hình thường **không có tiếng** — tiếng nằm ở rendition `#EXT-X-MEDIA:TYPE=AUDIO`
/// mà chỉ master khai — nên chốt m3u8 đầu tiên bắt được có thể ra hình mà mất tiếng. Vì vậy tải nội dung từng ứng
/// viên (nhỏ, cùng header với kết quả, có hạn chót) rồi ưu tiên master; không có master hoặc không tải được thì giữ
/// thứ tự bắt được (ứng viên đầu).
///
/// Không gắn actor: tải và phân loại chạy ngoài main. Kết quả chỉ gồm chỉ số + câu tóm tắt để log (không chứa URL).
enum VideoHLSPlaylistProbe {
    struct Choice: Sendable {
        /// Chỉ số trong mảng ứng viên truyền vào (luôn hợp lệ khi mảng không rỗng).
        let index: Int
        /// Mọi ứng viên theo thứ tự nên thử (phần tử đầu = `index`): master có `#EXT-X-MEDIA:TYPE=AUDIO` → master →
        /// playlist con → chưa rõ loại; cùng nhóm thì giữ thứ tự bắt được. Phần sau phần tử đầu là link dự phòng khi
        /// item phát ra hình mà mất tiếng (`VideoSourceResolution`).
        let ranked: [Int]
        /// Nhãn loại theo chỉ số ứng viên (`master+AUDIO`, `media`…) — không chứa URL.
        let labels: [String]
        /// Loại playlist đã chọn và loại từng ứng viên — không chứa URL.
        let summary: String
    }

    private enum Kind: Sendable {
        case master(hasAudioRendition: Bool)
        case media
        case notPlaylist
        case unavailable

        var isMaster: Bool {
            if case .master = self { return true }
            return false
        }

        var label: String {
            switch self {
            case .master(let hasAudioRendition): return hasAudioRendition ? "master+AUDIO" : "master"
            case .media: return "media"
            case .notPlaylist: return "không phải m3u8"
            case .unavailable: return "không tải được"
            }
        }

        /// Thứ tự ưu tiên khi xếp hạng (nhỏ hơn = thử trước).
        var rank: Int {
            switch self {
            case .master(let hasAudioRendition): return hasAudioRendition ? 0 : 1
            case .media: return 2
            case .unavailable: return 3
            case .notPlaylist: return 4
            }
        }
    }

    private struct Probed: Sendable {
        let index: Int
        let kind: Kind
    }

    /// Hạn chót tải mỗi playlist; cả lượt dò cũng không vượt quá mức này (cộng nửa giây).
    static let fetchTimeout: TimeInterval = 4
    /// Playlist thật chỉ vài KB; server trả thứ khác thì chỉ đọc phần đầu.
    private static let maxPlaylistBytes = 512 * 1024

    static func choose(among candidates: [VideoMediaSniffer.Result]) async -> Choice {
        let kinds = await probe(candidates)
        // Sắp xếp ổn định theo (hạng, thứ tự bắt được): không có master thì vẫn giữ ứng viên đầu như trước.
        let ranked = kinds.indices.sorted { (kinds[$0].rank, $0) < (kinds[$1].rank, $1) }
        let index = ranked.first { kinds[$0].isMaster } ?? 0
        let ordered = [index] + ranked.filter { $0 != index }
        let chosen = kinds.indices.contains(index) ? kinds[index] : Kind.unavailable
        let description: String
        switch chosen {
        case .master(let hasAudioRendition):
            description = hasAudioRendition
                ? "playlist gốc (master), có #EXT-X-MEDIA:TYPE=AUDIO"
                : "playlist gốc (master), không có #EXT-X-MEDIA:TYPE=AUDIO (tiếng gộp trong từng biến thể)"
        case .media:
            description = "playlist con (media) vì không có master trong ứng viên ⇒ giữ ứng viên đầu"
        case .notPlaylist, .unavailable:
            description = "ứng viên đầu, chưa rõ loại (\(chosen.label))"
        }
        let list = kinds.enumerated().map { "#\($0.offset + 1) \($0.element.label)" }.joined(separator: ", ")
        return Choice(
            index: index,
            ranked: kinds.isEmpty ? [] : ordered,
            labels: kinds.map { $0.label },
            summary: "Chọn \(description) — ứng viên \(index + 1)/\(candidates.count) [\(list)]"
        )
    }

    /// Nhãn loại của một playlist text (`master+AUDIO`, `master`, `media`, `không phải m3u8`) — dùng cho log chẩn đoán
    /// của playlist do tiện ích trả thẳng (`hlsText`).
    static func label(ofPlaylist text: String) -> String {
        classify(text).label
    }

    // MARK: - Luồng hình do tiện ích trả thẳng (`VideoAudioRenditionComposer`)

    /// Loại một playlist đơn lẻ, không cần biết có rendition tiếng hay không.
    enum Shape: Sendable {
        /// Playlist gốc (có `#EXT-X-STREAM-INF`).
        case master
        /// Playlist con (không có `#EXT-X-STREAM-INF`).
        case media
        /// Tải được nhưng không mở đầu bằng `#EXTM3U`.
        case notPlaylist
        /// Lỗi mạng, mã HTTP ngoài 2xx hoặc quá hạn chót.
        case unavailable
    }

    static func shape(ofPlaylist text: String) -> Shape {
        shape(of: classify(text))
    }

    /// Tải một playlist (cùng `headers`) rồi phân loại; cả lượt không vượt `fetchTimeout` + 0,5 giây (timeout của
    /// `URLRequest` chỉ là thời gian chờ rỗi, DNS/kết nối treo vẫn có thể lâu hơn).
    static func shape(ofRemote url: URL, headers: [String: String]) async -> Shape {
        let kind = await withTaskGroup(of: Kind?.self, returning: Kind.self) { group in
            group.addTask {
                await VideoHLSPlaylistProbe.kind(url: url, headers: headers)
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64((VideoHLSPlaylistProbe.fetchTimeout + 0.5) * 1_000_000_000))
                return nil
            }
            let first: Kind? = await group.next() ?? nil
            group.cancelAll()
            return first ?? .unavailable
        }
        return shape(of: kind)
    }

    private static func shape(of kind: Kind) -> Shape {
        switch kind {
        case .master: return .master
        case .media: return .media
        case .notPlaylist: return .notPlaylist
        case .unavailable: return .unavailable
        }
    }

    // MARK: - Tải & phân loại

    private static func probe(_ candidates: [VideoMediaSniffer.Result]) async -> [Kind] {
        guard !candidates.isEmpty else { return [] }
        return await withTaskGroup(of: Probed?.self, returning: [Kind].self) { group in
            for (index, candidate) in candidates.enumerated() {
                group.addTask {
                    let kind = await VideoHLSPlaylistProbe.kind(url: candidate.url, headers: candidate.headers)
                    return Probed(index: index, kind: kind)
                }
            }
            // Hạn chót chung: mạng treo (DNS, kết nối) cũng không giữ trình phát chờ lâu hơn `fetchTimeout`.
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64((VideoHLSPlaylistProbe.fetchTimeout + 0.5) * 1_000_000_000))
                return nil
            }
            var kinds = Array(repeating: Kind.unavailable, count: candidates.count)
            var remaining = candidates.count
            while remaining > 0, let next = await group.next() {
                guard let finished = next else { break }
                kinds[finished.index] = finished.kind
                remaining -= 1
            }
            group.cancelAll()
            return kinds
        }
    }

    private static func kind(url: URL, headers: [String: String]) async -> Kind {
        var request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: fetchTimeout
        )
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                return .unavailable
            }
            return classify(String(decoding: data.prefix(maxPlaylistBytes), as: UTF8.self))
        } catch {
            return .unavailable
        }
    }

    private static func classify(_ text: String) -> Kind {
        let body = VideoDataURI.stripBOM(text).trimmingCharacters(in: .whitespacesAndNewlines)
        guard body.hasPrefix("#EXTM3U") else { return .notPlaylist }
        guard body.contains("#EXT-X-STREAM-INF") else { return .media }
        // Thứ tự thuộc tính không cố định ⇒ xét cả dòng `#EXT-X-MEDIA:` thay vì khớp nguyên chuỗi `…:TYPE=AUDIO`.
        let hasAudioRendition = body.components(separatedBy: .newlines).contains { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.hasPrefix("#EXT-X-MEDIA:") && trimmed.uppercased().contains("TYPE=AUDIO")
        }
        return .master(hasAudioRendition: hasAudioRendition)
    }
}
