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
        let index = kinds.firstIndex { $0.isMaster } ?? 0
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
            summary: "Chọn \(description) — ứng viên \(index + 1)/\(candidates.count) [\(list)]"
        )
    }

    // MARK: - Tải & phân loại

    private static func probe(_ candidates: [VideoMediaSniffer.Result]) async -> [Kind] {
        guard !candidates.isEmpty else { return [] }
        return await withTaskGroup(of: Probed?.self, returning: [Kind].self) { group in
            for (index, candidate) in candidates.enumerated() {
                group.addTask {
                    let kind = await VideoHLSPlaylistProbe.kind(of: candidate)
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

    private static func kind(of candidate: VideoMediaSniffer.Result) async -> Kind {
        var request = URLRequest(
            url: candidate.url,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: fetchTimeout
        )
        for (name, value) in candidate.headers {
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
