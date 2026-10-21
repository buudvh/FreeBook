import Foundation

/// Kiểm tra JSON nguồn do người dùng sửa (màn "Sửa JSON nguồn") trước khi ghi, và định dạng lại để hiển thị.
///
/// Thứ tự kiểm: JSON **chuẩn** (`JSONSerialization` — báo được dòng lỗi; trình sửa luôn mở bản chuẩn đã lưu nên không
/// cần parser lỏng) → đúng **một** object → cùng luật nhận nguồn với bộ nhập (`LegadoSourceImporter.skipReason`: có
/// URL, có tên, loại 0/2/4, nguồn chữ đủ rule tối thiểu). Hàm thuần, gọi được từ thread bất kỳ.
enum LegadoSourceJSONValidator {
    struct Issue: Error, Sendable, Equatable {
        let message: String
        /// Dòng (đếm từ 1) khi trình phân tích JSON báo được vị trí.
        let line: Int?

        var displayText: String {
            guard let line else { return message }
            return "Dòng \(line): \(message)"
        }
    }

    /// Nguồn đã parse (với `rawJSON` = bytes chuẩn hoá: khoá sắp xếp, không escape `/`).
    static func validate(_ text: String) -> Result<LegadoBookSource, Issue> {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure(Issue(message: "Nội dung trống.", line: nil))
        }
        let data = Data(text.utf8)
        let parsed: Any
        do {
            parsed = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            return .failure(issue(from: error as NSError, data: data))
        }
        guard let object = parsed as? [String: Any] else {
            return .failure(Issue(message: "JSON phải là một object nguồn ({…}), không phải mảng hay giá trị đơn.", line: nil))
        }
        let source = LegadoBookSource(jsonObject: object)
        if let reason = LegadoSourceImporter.skipReason(for: source, object: object) {
            return .failure(Issue(message: "Nguồn không hợp lệ: \(reason.label).", line: nil))
        }
        return .success(source)
    }

    /// Văn bản thụt 2 dấu cách, khoá sắp xếp — dạng mở trong trình sửa. Dữ liệu không parse được ⇒ chuỗi nguyên văn.
    static func prettyText(fromData data: Data) -> String {
        guard let object = LegadoModelJSON.parseDocument(data: data), let text = prettyText(object) else {
            return String(decoding: data, as: UTF8.self)
        }
        return text
    }

    /// Định dạng lại văn bản đang sửa; `nil` khi chưa phải JSON chuẩn.
    static func prettyText(fromText text: String) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: Data(text.utf8), options: [.fragmentsAllowed]) else {
            return nil
        }
        return prettyText(object)
    }

    static func prettyText(_ object: Any) -> String? {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(
                withJSONObject: object,
                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
              ) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: - Vị trí lỗi

    /// Lấy dòng lỗi từ thông báo của `JSONSerialization` ("… around line 3, column 5.") hoặc từ chỉ số byte
    /// `NSJSONSerializationErrorIndex` (đếm `\n` trước vị trí đó).
    private static func issue(from error: NSError, data: Data) -> Issue {
        let detail = (error.userInfo["NSDebugDescription"] as? String) ?? error.localizedDescription
        var line = firstNumber(after: "line ", in: detail)
        if line == nil, let index = error.userInfo["NSJSONSerializationErrorIndex"] as? Int, index >= 0 {
            let prefix = data.prefix(min(index, data.count))
            line = prefix.reduce(1) { $1 == 0x0A ? $0 + 1 : $0 }
        }
        return Issue(message: "JSON không hợp lệ — \(detail)", line: line)
    }

    private static func firstNumber(after marker: String, in text: String) -> Int? {
        guard let range = text.range(of: marker, options: .caseInsensitive) else { return nil }
        let digits = text[range.upperBound...].prefix { $0.isNumber }
        return Int(digits)
    }
}
