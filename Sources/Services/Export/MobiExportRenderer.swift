import Foundation

/// Xuất MOBI (PalmDB + PalmDOC không nén) cho Kindle.
///
/// MOBI đặt bảng offset của mọi record ở **đầu** file, nên không ghi thẳng ra file đích được: renderer gom
/// phần HTML vào một file tạm trong `temporaryDirectory` (đỉnh RAM vẫn bằng một chương), rồi ở `finish()`
/// mới dựng header và copy lại từng khối 4096 byte sang file đích.
///
/// Mục lục dùng cơ chế `filepos` của MOBI6: khối mục lục nằm ở **cuối** text nên khi ghi nó đã biết offset
/// của mọi chương; còn `<reference type="toc">` trong `<head>` được chừa sẵn 10 chữ số và vá đúng chỗ lúc
/// copy — vá cùng độ dài nên không dịch chuyển bất kỳ offset nào.
final class MobiExportRenderer: ExportRenderer {
    private struct ChapterAnchor {
        let title: String
        let filepos: Int
    }

    /// 65535 record × 4096 byte — trần của field `recordCount` (UInt16) trong PalmDOC header.
    private static let maxTextLength = 65_535 * MobiHeaderBuilder.textRecordSize
    private static let fileposDigits = 10

    private let request: BookExportRequest
    private let targetURL: URL
    private let textStage: ExportStagingFile
    private let textStageURL: URL
    private var anchors: [ChapterAnchor] = []
    /// Vị trí (byte) của 10 chữ số `filepos` trong `<head>` cần vá ở `finish()`.
    private var guideFileposOffset = 0

    var writtenChapterCount: Int { anchors.count }
    var hasContent: Bool { !anchors.isEmpty }

    init(request: BookExportRequest) throws {
        self.request = request
        self.targetURL = try ExportFileNaming.targetURL(bookTitle: request.bookTitle, format: .mobi)
        self.textStageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("mobi-\(UUID().uuidString).text")
        self.textStage = try ExportStagingFile(targetURL: textStageURL)

        try textStage.write("<html><head><guide><reference type=\"toc\" title=\"Mục lục\" filepos=")
        guideFileposOffset = textStage.bytesWritten
        try textStage.write(String(repeating: "0", count: Self.fileposDigits))
        try textStage.write("/></guide></head><body>")
    }

    func append(_ chapter: ExportChapterPayload) throws {
        let filepos = textStage.bytesWritten
        var block = anchors.isEmpty ? "" : "<mbp:pagebreak/>"
        block += "<h1>\(ExportTextEscaper.xml(chapter.title))</h1>"
        for paragraph in ExportParagraphSplitter.paragraphs(from: chapter.content) {
            block += "<p>\(ExportTextEscaper.xml(paragraph))</p>"
        }
        try textStage.write(block)
        anchors.append(ChapterAnchor(title: chapter.title, filepos: filepos))
    }

    func finish() throws -> ExportArtifact {
        guard hasContent else {
            discard()
            throw ExportRenderError.emptyExport
        }

        let tocFilepos = textStage.bytesWritten
        try textStage.write(tocBlock())
        try textStage.write("</body></html>")

        let textLength = textStage.bytesWritten
        guard textLength <= Self.maxTextLength else {
            discard()
            throw ExportRenderError.sizeLimitExceeded(
                "Bản xuất MOBI vượt giới hạn \(Self.maxTextLength / (1024 * 1024)) MB, hãy chọn định dạng EPUB."
            )
        }
        _ = try textStage.commit()
        defer { try? FileManager.default.removeItem(at: textStageURL) }

        let output = try ExportStagingFile(targetURL: targetURL)
        do {
            try writeMobi(to: output, textLength: textLength, tocFilepos: tocFilepos)
        } catch {
            output.discard()
            throw error
        }
        let url = try output.commit()
        return ExportArtifact(fileURL: url, format: .mobi, chapterCount: anchors.count)
    }

    func discard() {
        textStage.discard()
        try? FileManager.default.removeItem(at: textStageURL)
    }

    // MARK: - Ghi file đích

    private func writeMobi(to output: ExportStagingFile, textLength: Int, tocFilepos: Int) throws {
        let recordSize = MobiHeaderBuilder.textRecordSize
        let textRecordCount = (textLength + recordSize - 1) / recordSize
        let cover = request.coverJpegData.flatMap { $0.isEmpty ? nil : $0 }
        let uniqueId = UInt32.random(in: 1...UInt32.max)

        let record0 = MobiHeaderBuilder.record0(
            MobiHeaderBuilder.Layout(
                textLength: textLength,
                textRecordCount: textRecordCount,
                fullName: request.bookTitle,
                author: request.author,
                desc: request.desc,
                firstNonBookIndex: 1 + textRecordCount,
                firstImageIndex: 1 + textRecordCount,
                coverImageOffset: cover == nil ? nil : 0,
                lastContentRecord: textRecordCount,
                uniqueId: uniqueId
            )
        )

        // Kích thước mọi record, theo đúng thứ tự trong file — cơ sở tính bảng offset ở đầu file.
        var sizes: [Int] = [record0.count]
        for index in 0..<textRecordCount {
            sizes.append(min(recordSize, textLength - index * recordSize))
        }
        if let cover {
            sizes.append(cover.count)
        }
        sizes.append(4) // record EOF

        try output.write(palmHeader(recordCount: sizes.count, sizes: sizes, uniqueId: uniqueId))
        try output.write(record0)
        try copyTextRecords(to: output, textLength: textLength, tocFilepos: tocFilepos)
        if let cover {
            try output.write(cover)
        }
        try output.write(Data([0xE9, 0x8E, 0x0D, 0x0A])) // record EOF chuẩn của MOBI
    }

    /// PalmDB header 78 byte + bảng record 8 byte/record + 2 byte đệm.
    private func palmHeader(recordCount: Int, sizes: [Int], uniqueId: UInt32) -> Data {
        var data = Data()
        let name = Self.palmName(from: request.bookTitle)
        data.append(name)
        BigEndianBytes.appendZeros(32 - name.count, to: &data)          // tên 32 byte, đệm 0
        BigEndianBytes.appendUInt16(0, to: &data)                       // attributes
        BigEndianBytes.appendUInt16(0, to: &data)                       // version
        let palmDate = UInt32(max(0, Date().timeIntervalSince1970 + 2_082_844_800))
        BigEndianBytes.appendUInt32(palmDate, to: &data)                // creation date
        BigEndianBytes.appendUInt32(palmDate, to: &data)                // modification date
        BigEndianBytes.appendUInt32(0, to: &data)                       // last backup date
        BigEndianBytes.appendUInt32(0, to: &data)                       // modification number
        BigEndianBytes.appendUInt32(0, to: &data)                       // appInfoID
        BigEndianBytes.appendUInt32(0, to: &data)                       // sortInfoID
        BigEndianBytes.appendSignature("BOOK", to: &data)               // type
        BigEndianBytes.appendSignature("MOBI", to: &data)               // creator
        BigEndianBytes.appendUInt32(uniqueId, to: &data)                // uniqueIDSeed
        BigEndianBytes.appendUInt32(0, to: &data)                       // nextRecordListID
        BigEndianBytes.appendUInt16(UInt16(recordCount), to: &data)     // số record

        var offset = 78 + 8 * recordCount + 2
        for index in 0..<recordCount {
            BigEndianBytes.appendUInt32(UInt32(offset), to: &data)
            BigEndianBytes.appendUInt32(UInt32(index * 2), to: &data)   // attributes 0 + uniqueID
            offset += sizes[index]
        }
        BigEndianBytes.appendZeros(2, to: &data)
        return data
    }

    /// Copy text từ file tạm sang file đích theo từng record, vá `filepos` của mục lục khi đi qua nó.
    private func copyTextRecords(to output: ExportStagingFile, textLength: Int, tocFilepos: Int) throws {
        let handle = try FileHandle(forReadingFrom: textStageURL)
        defer { try? handle.close() }

        let digits = Data(String(format: "%0\(Self.fileposDigits)d", tocFilepos).utf8)
        var written = 0
        while written < textLength {
            let wanted = min(MobiHeaderBuilder.textRecordSize, textLength - written)
            guard var chunk = try handle.read(upToCount: wanted), !chunk.isEmpty else { break }
            if guideFileposOffset >= written,
               guideFileposOffset + digits.count <= written + chunk.count {
                let lower = chunk.startIndex + (guideFileposOffset - written)
                chunk.replaceSubrange(lower..<(lower + digits.count), with: digits)
            }
            try output.write(chunk)
            written += chunk.count
        }
    }

    private func tocBlock() -> String {
        var block = "<mbp:pagebreak/><h1>Mục lục</h1>"
        for anchor in anchors {
            let filepos = String(format: "%0\(Self.fileposDigits)d", anchor.filepos)
            block += "<p><a filepos=\(filepos)>\(ExportTextEscaper.xml(anchor.title))</a></p>"
        }
        return block
    }

    /// Tên PalmDB chỉ nhận ASCII in được và tối đa 31 byte + null.
    private static func palmName(from title: String) -> Data {
        var name = ""
        for scalar in title.unicodeScalars where scalar.value >= 0x20 && scalar.value < 0x7F {
            name.unicodeScalars.append(scalar)
        }
        name = name.trimmingCharacters(in: .whitespaces)
        if name.isEmpty {
            name = "FreeBook"
        }
        return Data(name.utf8.prefix(31))
    }
}
