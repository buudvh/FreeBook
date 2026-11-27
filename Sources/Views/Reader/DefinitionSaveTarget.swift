import Foundation

/// Nơi lưu đang chọn ở panel Dịch (Reader + truyện tranh — `ReaderDefinitionOverlayView`): NE / VP / PN.
///
/// Chỉ **lựa chọn đang dùng** có ba giá trị. Ghim mặc định vẫn là `Bool` cũ `pinnedSaveAsNameType` (`@AppStorage`,
/// true = NE, false = VP): anh Bửu chốt PN **không** ghim được — mở panel / đổi vùng chọn luôn lấy NE hoặc VP theo ghim.
/// PN chỉ có bản chung ⇒ cụm R | C mờ, không bấm được; lựa chọn R / C giữ nguyên để chọn lại NE / VP thì về như cũ.
enum DefinitionSaveTarget: Equatable, Sendable {
    case name
    case vietPhrase
    case pronoun

    /// Lựa chọn mặc định theo ghim NE / VP.
    init(pinnedAsName: Bool) {
        self = pinnedAsName ? .name : .vietPhrase
    }

    /// Pronouns không có bản riêng truyện.
    var hasBookScope: Bool { self != .pronoun }

    /// Lưu `word=meaning`. NE / VP ⇒ lớp sửa đổi (`saveCustomEntry`, `bookId` = phạm vi R / C). PN ⇒ file Pronouns gốc qua
    /// hàng đợi `GlobalDictionaryEditor` (từ đã có ⇒ thay nghĩa; dựng lại `.dat`, nạp lại riêng Pronouns, xoá cache dịch,
    /// báo đổi từ điển), bỏ qua `bookId`; nghĩa chuẩn hoá như NE / VP (`|` `¦` ⇒ `/`, cắt khoảng trắng từng nghĩa).
    func save(word: String, meaning: String, bookId: String?) async throws {
        switch self {
        case .name, .vietPhrase:
            try await TranslationManager.shared.saveCustomEntry(
                word: word, meaning: meaning, isName: self == .name, bookId: bookId
            )
        case .pronoun:
            let value = DictionaryTextFileStore.normalizeMeaning(meaning)
            guard !value.isEmpty else { return }
            try await GlobalDictionaryEditor.shared.save(key: word, value: value, replacing: nil, type: "pronouns")
        }
    }
}
