import Foundation

/// Đổi "vị trí người dùng" thành **chỉ số chunk** trong `[TTSParagraph]` — tách khỏi `TTSManager` (đợt 7, 1.3.486).
///
/// Ba hàm là **ba ngữ nghĩa khác nhau**, cố ý giữ riêng (không gộp): `targetChunkIndex` ưu tiên `resumeIdentity`
/// rồi `sourceRange`; `indexForParagraphPosition` chỉ khớp `paragraphIndex` và nhận ra tiêu đề qua
/// `paragraphs.first?.paragraphIndex == -1`; `reanchorAfterSettings` so **`range`** (toạ độ hiển thị) với chunk cũ
/// sau khi dựng lại đoạn, chấp nhận `range.length == 0`, và nhận cờ tiêu đề từ caller. Thân hàm chuyển nguyên văn.
/// `paragraphIndex` là ID dòng **thưa** (tiêu đề = -1), không phải chỉ số mảng (CLAUDE.md).
enum TTSChunkPositionMapper {
    static func targetChunkIndex(
        in paragraphs: [TTSParagraph],
        startParagraphIndex: Int,
        startTextOffset: Int? = nil,
        resumeIdentity: TTSChunkResumeIdentity? = nil
    ) -> Int {
        guard !paragraphs.isEmpty else { return 0 }

        if let identity = resumeIdentity {
            if identity.sourceLineId == -1 {
                return 0
            }
            let matching = paragraphs.enumerated().filter { $0.element.paragraphIndex == identity.sourceLineId }
            if !matching.isEmpty {
                if let found = matching.first(where: {
                    let range = $0.element.sourceRange
                    return range.location != NSNotFound && range.location <= identity.sourceOffset && identity.sourceOffset < NSMaxRange(range)
                }) {
                    return found.offset
                }
                if identity.chunkOrdinal >= 0 && identity.chunkOrdinal < matching.count {
                    return matching[identity.chunkOrdinal].offset
                }
                return matching.first!.offset
            }
        }

        if startParagraphIndex == -1 {
            return 0
        }
        let matchingChunks = paragraphs.enumerated().filter { $0.element.paragraphIndex == startParagraphIndex }
        if matchingChunks.isEmpty {
            return 0
        }

        if let offset = startTextOffset, offset != NSNotFound, offset >= 0 {
            if let exact = matchingChunks.first(where: {
                let r = $0.element.sourceRange.location != NSNotFound ? $0.element.sourceRange : $0.element.range
                return r.location <= offset && offset < NSMaxRange(r)
            }) {
                return exact.offset
            }
            if let exactRange = matchingChunks.first(where: {
                $0.element.range.location <= offset && offset < NSMaxRange($0.element.range)
            }) {
                return exactRange.offset
            }
        }
        return matchingChunks.first!.offset
    }

    /// Trả `-1`-an-toàn như code cũ: caller vẫn kiểm `0 ..< paragraphs.count` trước khi dùng.
    static func indexForParagraphPosition(in paragraphs: [TTSParagraph], paragraphIndex: Int) -> Int {
        let titleInserted = paragraphs.first?.paragraphIndex == -1
        var targetIdx = -1
        if paragraphIndex == -1 {
            targetIdx = 0
        } else if let idx = paragraphs.firstIndex(where: { $0.paragraphIndex == paragraphIndex }) {
            targetIdx = idx
        } else {
            targetIdx = titleInserted ? 1 : 0
        }
        return targetIdx
    }

    static func reanchorAfterSettings(
        in paragraphs: [TTSParagraph],
        savedParagraphIdentity: Int,
        savedChunkRange: NSRange,
        savedChunkLocation: Int,
        titleInserted: Bool
    ) -> Int {
        let targetIdx: Int
        if savedParagraphIdentity == -1 {
            targetIdx = 0
        } else if let exactMatch = paragraphs.firstIndex(where: {
            $0.paragraphIndex == savedParagraphIdentity && $0.range == savedChunkRange
        }) {
            // Khớp chính xác chunk cũ khi chunkLength không đổi
            targetIdx = exactMatch
        } else if let rangeMatch = paragraphs.firstIndex(where: {
            $0.paragraphIndex == savedParagraphIdentity &&
            $0.range.location <= savedChunkLocation &&
            (savedChunkLocation < $0.range.location + $0.range.length || $0.range.length == 0)
        }) {
            // Khớp chunk mới bao hàm vị trí từ đầu tiên của chunk cũ khi chunkLength thay đổi
            targetIdx = rangeMatch
        } else if let parentFirstIdx = paragraphs.firstIndex(where: { $0.paragraphIndex == savedParagraphIdentity }) {
            // Fallback: chunk đầu tiên của paragraph đó
            targetIdx = parentFirstIdx
        } else {
            targetIdx = (titleInserted && paragraphs.count > 1) ? 1 : 0
        }
        return targetIdx
    }
}
