import Foundation

/// Tiện ích diễn giải giá trị rule dùng chung cho các luồng (spec §5.4.3, §5.3.3, §5.1.2).
enum LegadoRuleValue {
    private static let falsyWords: Set<String> = ["", "false", "0", "null", "undefined", "no"]

    /// Luật truthy của cờ `isVolume`/`isVip`/`isPay`/`canReName`: chuỗi sau trim, so không phân biệt hoa thường;
    /// `""`, `false`, `0`, `null`, `undefined`, `no` là **false**, còn lại **true** (`¥false` là true — đúng ý tác giả).
    static func isTruthy(_ value: String) -> Bool {
        !falsyWords.contains(value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }

    /// Gộp khoảng trắng liên tiếp thành một dấu cách và trim (dùng cho `name`/`author`, §5.1.2).
    static func collapseWhitespace(_ value: String) -> String {
        value.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    /// Tách nhãn `kind` theo `,` `，` xuống dòng; bỏ rỗng, bỏ trùng, giữ thứ tự (§5.1.2).
    static func splitKinds(_ value: String) -> [String] {
        var seen = Set<String>()
        var output: [String] = []
        for part in value.split(whereSeparator: { $0 == "," || $0 == "，" || $0 == "\n" }) {
            let tag = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !tag.isEmpty, seen.insert(tag).inserted else { continue }
            output.append(tag)
        }
        return output
    }
}
