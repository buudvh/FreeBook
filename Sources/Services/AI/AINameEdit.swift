import Foundation

/// Một lần sửa danh sách name AI bằng nút bút chì của sheet "Duyệt tên riêng & VP" (1.3.780), hoặc một lần ✕ xoá đi
/// sau lần sửa đó. Cùng một phép áp lên **ba** chỗ để chúng luôn khớp nhau:
/// - danh sách đang duyệt của sheet (`applied(to:)`);
/// - nội dung tin nguồn (`applied(toContent:)`) — sheet dựng lại danh sách từ nội dung tin mỗi lần mở;
/// - danh sách tên đầy đủ mà lượt quét / "Thử lại" dựng lại nội dung tin (`AIRuntimeCoordinator+NameEdits` áp lại cả
///   chuỗi sửa, đúng thứ tự, sau bộ lọc khoá đã ✕).
///
/// Khoá so khớp là vế trái `từ=nghĩa` đã trim — cùng luật với `AIRuntimeCoordinator.nameKey` và cách tách dòng của
/// `ReaderAINameReviewSheet`. Khoá trong danh sách là duy nhất: phép nào làm hai mục trùng khoá thì giữ mục vừa sửa.
/// Áp lại một phép lên danh sách đã có nó thì ra cùng kết quả (lượt quét áp lại cả chuỗi mỗi nhịp tiến độ).
/// `public` vì `ReaderAINameReviewSheet` (public) nhận nó qua `init`.
public enum AINameEdit: Sendable, Equatable {
    /// Đổi nghĩa của mục `key`; `newKey != key` ⇒ đổi luôn khoá. Không còn mục `key` mà đã có `newKey` ⇒ đổi nghĩa
    /// mục `newKey` (phép đã áp từ trước). Không có cả hai ⇒ không làm gì.
    case update(key: String, newKey: String, meaning: String)
    /// Thêm mục `key` ngay sau mục `anchorKey` (không còn mục đó ⇒ cuối danh sách). Đã có `key` ⇒ chỉ đổi nghĩa.
    case add(key: String, meaning: String, anchorKey: String)
    /// Bỏ mục `key` — chỉ ghi vào chuỗi sửa khi tin đã có lần sửa trước đó (`AIRuntimeCoordinator.forgetName`).
    case remove(key: String)

    /// Nhãn loại của mục thêm mới — như mục tách từ nội dung tin (`ReaderAINameReviewSheet.loadAndDecorateNames`).
    static let addedCategory = "Tên riêng"

    static func key(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Khoá mà phép này để lại trong danh sách (`nil` với `.remove`).
    var resultingKey: String? {
        switch self {
        case let .update(_, newKey, _): return newKey
        case let .add(key, _, _): return key
        case .remove: return nil
        }
    }

    /// Phép có thể đưa một khoá mới vào danh sách (đổi khoá / thêm mục) ⇒ cờ NE/VP của mục đó phải tra lại.
    var mayIntroduceKey: Bool {
        switch self {
        case let .update(key, newKey, _): return key != newKey
        case .add: return true
        case .remove: return false
        }
    }

    // MARK: - Danh sách

    /// Mục được sửa / thêm luôn được chọn sẵn để Lưu. Mục đổi khoá mất cờ NE/VP cũ (sheet tra lại ngoài main).
    func applied(to names: [AIExtractedName]) -> [AIExtractedName] {
        switch self {
        case let .update(key, newKey, meaning):
            guard let index = names.firstIndex(where: { Self.key($0.original) == key })
                    ?? names.firstIndex(where: { Self.key($0.original) == newKey }) else { return names }
            var result = names
            var item = result[index]
            if Self.key(item.original) != newKey {
                item.original = newKey
                item.hasInBookNames = false
                item.hasInBookVP = false
            }
            item.suggestedMeaning = meaning
            item.isSelected = true
            result[index] = item
            let keptId = item.id
            result.removeAll { $0.id != keptId && [key, newKey].contains(Self.key($0.original)) }
            return result

        case let .add(key, meaning, anchorKey):
            if names.contains(where: { Self.key($0.original) == key }) {
                return AINameEdit.update(key: key, newKey: key, meaning: meaning).applied(to: names)
            }
            let added = AIExtractedName(
                original: key,
                suggestedMeaning: meaning,
                category: Self.addedCategory,
                occurrenceCount: 1,
                isSelected: true
            )
            var result = names
            let position = result.firstIndex(where: { Self.key($0.original) == anchorKey }).map { $0 + 1 } ?? result.endIndex
            result.insert(added, at: position)
            return result

        case let .remove(key):
            return names.filter { Self.key($0.original) != key }
        }
    }

    // MARK: - Nội dung tin

    /// Sửa các dòng `từ=nghĩa` của tin, giữ nguyên mọi dòng khác (tiêu đề, lời AI). Dòng của mục được sửa thay **tại
    /// chỗ** dòng đầu tiên mang khoá cũ (không có thì khoá mới); các dòng còn lại mang khoá cũ hoặc khoá mới bị bỏ — kể cả
    /// dòng sheet không hiện (nghĩa lẫn chữ Hán), như nút ✕. Mục thêm mới chèn ngay sau dòng đầu tiên của `anchorKey`.
    func applied(toContent content: String) -> String {
        var lines = content.components(separatedBy: "\n")
        switch self {
        case let .update(key, newKey, meaning):
            guard let anchor = lines.firstIndex(where: { Self.lineKey($0) == key })
                    ?? lines.firstIndex(where: { Self.lineKey($0) == newKey }) else { return content }
            lines[anchor] = "\(newKey)=\(meaning)"
            let dropped = Set([key, newKey])
            return lines.enumerated()
                .filter { index, line in
                    guard index != anchor, let found = Self.lineKey(line) else { return true }
                    return !dropped.contains(found)
                }
                .map(\.element)
                .joined(separator: "\n")

        case let .add(key, meaning, anchorKey):
            if lines.contains(where: { Self.lineKey($0) == key }) {
                return AINameEdit.update(key: key, newKey: key, meaning: meaning).applied(toContent: content)
            }
            let line = "\(key)=\(meaning)"
            if let anchor = lines.firstIndex(where: { Self.lineKey($0) == anchorKey }) {
                lines.insert(line, at: anchor + 1)
                return lines.joined(separator: "\n")
            }
            return content.isEmpty ? line : content + "\n" + line

        case let .remove(key):
            return lines.filter { Self.lineKey($0) != key }.joined(separator: "\n")
        }
    }

    /// Vế trái đã trim của một dòng có dấu `=`; dòng không có `=` ⇒ `nil` (không phải dòng name).
    private static func lineKey(_ line: String) -> String? {
        guard let eqIdx = line.firstIndex(of: "=") else { return nil }
        return key(String(line[..<eqIdx]))
    }
}
