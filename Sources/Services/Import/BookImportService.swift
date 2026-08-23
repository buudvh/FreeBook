import Foundation

/// Điểm vào **duy nhất** của việc bóc tách file sách người dùng nhập từ máy.
///
/// View chỉ gọi `parse(_:)` rồi nhận `Result`; toàn bộ chuyện nhận diện format, giải mã, đọc mục lục
/// và tách chương nằm dưới tầng Services. Lỗi trả bằng `throw` (không gọi `ToastManager` — luật
/// `SERVICE_TOAST_COUPLING`), thông báo đã là tiếng Việt để View đổ thẳng vào toast.
enum BookImportService {
    /// Cách tách chương. `auto` để parser tự chọn theo độ tin cậy; ba giá trị còn lại là người dùng ép.
    enum StructureMode: String, CaseIterable, Identifiable, Sendable {
        /// Tự động: mục lục thật → thứ tự spine → quy tắc TOC.
        case auto
        /// Bắt buộc dùng mục lục nhúng trong file (NCX/nav của EPUB).
        case tocIndex
        /// Bắt buộc mỗi file nội dung trong spine là một chương.
        case spine
        /// Bắt buộc tách bằng regex quy tắc TOC như file TXT.
        case tocRules

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .auto: return "Tự động"
            case .tocIndex: return "Theo mục lục"
            case .spine: return "Theo thứ tự file"
            case .tocRules: return "Theo quy tắc TOC"
            }
        }
    }

    struct Request: Sendable {
        let tempFileUrl: URL
        let fileName: String
        /// Bảng mã người dùng chọn tay; `nil` = tự động. Override mọi khai báo trong file.
        let encodingOverride: TextEncodingOption?
        /// Tập quy tắc TOC người dùng chọn; rỗng = dùng quy tắc đang bật.
        let ruleIDs: Set<String>
        let structure: StructureMode

        init(
            tempFileUrl: URL,
            fileName: String,
            encodingOverride: TextEncodingOption? = nil,
            ruleIDs: Set<String> = [],
            structure: StructureMode = .auto
        ) {
            self.tempFileUrl = tempFileUrl
            self.fileName = fileName
            self.encodingOverride = encodingOverride
            self.ruleIDs = ruleIDs
            self.structure = structure
        }
    }

    struct Result: Sendable {
        let parsed: ParsedBook
        let format: BookImportFormat
        /// Bảng mã tự động khớp với file (để đánh dấu trong picker); `nil` khi format tự khai bảng mã.
        let autoDecodeID: String?
        let matchedRuleIDs: Set<String>
    }

    enum ImportError: LocalizedError {
        case decodeFailed
        case emptyContent
        case drmProtected
        case unsupportedCompression
        case malformed(String)

        var errorDescription: String? {
            switch self {
            case .decodeFailed:
                return "Định dạng file không hỗ trợ hoặc lỗi mã hóa ký tự."
            case .emptyContent:
                return "File văn bản không chứa nội dung hoặc cấu trúc chương hợp lệ."
            case .drmProtected:
                return "File có DRM, không thể nhập."
            case .unsupportedCompression:
                return "File dùng nén HUFF/CDIC, chưa hỗ trợ."
            case .malformed(let reason):
                return "File không đọc được: \(reason)"
            }
        }
    }

    static func parse(_ request: Request) async throws -> Result {
        let data: Data
        do {
            data = try Data(contentsOf: request.tempFileUrl)
        } catch {
            throw ImportError.malformed(error.localizedDescription)
        }
        guard !data.isEmpty else { throw ImportError.decodeFailed }

        let format = BookImportFormat.detect(fileName: request.fileName, data: data)
        let rules = resolvedRules(request.ruleIDs)

        switch format {
        case .txt:
            let text = try decodeText(data, override: request.encodingOverride, declaredCharset: nil)
            var parsed = TxtBookParser.parse(content: text, fileName: request.fileName, rules: rules)
            guard !parsed.chapters.isEmpty else { throw ImportError.emptyContent }
            parsed.structureNote = "Quy tắc TOC — \(parsed.chapters.count) chương"
            return Result(
                parsed: parsed,
                format: .txt,
                autoDecodeID: TextEncodingDecoder.detect(data)?.rawValue,
                matchedRuleIDs: matchedRules(in: text)
            )

        case .html:
            let charset = XhtmlTextExtractor.declaredCharsetName(in: data)
            let html = try decodeText(data, override: request.encodingOverride, declaredCharset: charset)
            let parsed = HtmlBookParser.parse(
                html: html,
                fileName: request.fileName,
                rules: rules,
                structure: request.structure
            )
            guard !parsed.chapters.isEmpty else { throw ImportError.emptyContent }
            return Result(
                parsed: parsed,
                format: .html,
                autoDecodeID: TextEncodingDecoder.detect(data)?.rawValue,
                matchedRuleIDs: matchedRules(in: probeText(parsed))
            )

        case .epub:
            let parsed = try EpubBookParser.parse(
                fileUrl: request.tempFileUrl,
                fileName: request.fileName,
                rules: rules,
                structure: request.structure
            )
            guard !parsed.chapters.isEmpty else { throw ImportError.emptyContent }
            return Result(
                parsed: parsed,
                format: .epub,
                autoDecodeID: nil,
                matchedRuleIDs: matchedRules(in: probeText(parsed))
            )

        case .mobi:
            let parsed = try MobiBookParser.parse(
                data: data,
                fileName: request.fileName,
                rules: rules,
                structure: request.structure,
                encodingOverride: request.encodingOverride
            )
            guard !parsed.chapters.isEmpty else { throw ImportError.emptyContent }
            return Result(
                parsed: parsed,
                format: .mobi,
                autoDecodeID: nil,
                matchedRuleIDs: matchedRules(in: probeText(parsed))
            )
        }
    }

    // MARK: - Helpers

    private static func resolvedRules(_ ruleIDs: Set<String>) -> [TOCRule] {
        guard !ruleIDs.isEmpty else { return TranslateUtils.getActiveTOCRules() }
        return TranslateUtils.getAllTOCRules().filter { ruleIDs.contains($0.id) }
    }

    private static func matchedRules(in content: String) -> Set<String> {
        return TranslateUtils.matchingRuleIDs(in: content, rules: TranslateUtils.getAllTOCRules())
    }

    /// Với các format có mục lục thật, chuỗi dò quy tắc TOC chỉ cần là danh sách tiêu đề chương —
    /// đủ để đánh dấu quy tắc nào khớp trong picker mà không phải quét lại toàn bộ nội dung sách.
    private static func probeText(_ parsed: ParsedBook) -> String {
        return parsed.chapters.prefix(500).map(\.title).joined(separator: "\n")
    }

    private static func decodeText(
        _ data: Data,
        override: TextEncodingOption?,
        declaredCharset: String?
    ) throws -> String {
        if let override {
            guard let text = TextEncodingDecoder.decode(data, using: override), !text.isEmpty else {
                throw ImportError.decodeFailed
            }
            return text
        }
        if let declaredCharset,
           let text = TextEncodingDecoder.decodeDeclared(data, charsetName: declaredCharset),
           !text.isEmpty {
            return text
        }
        let text = TextEncodingDecoder.decode(data)
        guard !text.isEmpty else { throw ImportError.decodeFailed }
        return text
    }
}
