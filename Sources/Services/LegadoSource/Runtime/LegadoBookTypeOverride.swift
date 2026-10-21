import Foundation

/// Ghi đè loại nội dung **theo từng sách** của nguồn Legado (spec §13.6): JS ghi `book.type = v` / `book.setType(v)`,
/// runtime lưu giá trị thô vào `LegadoBookState.typeOverride`; type này đổi giá trị đó thành loại màn hình của app.
///
/// - Router `BookContentDestination` chọn màn theo: ghi đè của sách > `bookSourceType` của nguồn. Loại được ghim lúc mở
///   màn, nên ghi đè mới (JS ghi trong `chapterList`/`content`) chỉ áp từ lần mở sau.
/// - `chap` của nguồn tranh/video vẫn chạy khi sách bị ghi đè thành chữ (`effectiveKind`).
/// - Audio, tệp và giá trị không rõ (`3`, bitmask không có bit đã biết) bị **bỏ qua** — dùng loại của nguồn: app chưa
///   có màn cho hai loại đó. Mỗi giá trị bị bỏ ghi một dòng log trong phiên chạy app.
/// - Gọi được từ thread bất kỳ: kho trạng thái giữ bộ nhớ; lần đầu với một sách chỉ đọc file sidecar nhỏ một lần.
final class LegadoBookTypeOverride: @unchecked Sendable {
    static let shared = LegadoBookTypeOverride()

    private let lock = NSLock()
    private var loggedValues: Set<Int> = []

    private init() {}

    /// Loại theo ghi đè đã lưu của `bookId`; `nil` khi nguồn không phải nguồn Legado đã cài, sách chưa có ghi đè, hoặc
    /// ghi đè không dùng được. Tiện ích JS: một lần tra bảng chụp kho tiện ích, không đụng kho trạng thái.
    func contentKind(bookId: String, packageId: String) -> ExtensionContentKind? {
        guard let id = LegadoSourceRuntime.nonEmpty(bookId),
              let ext = ExtensionLibraryRepository.snapshot(packageId: packageId),
              LegadoSourceIdentity.isLegado(ext) else { return nil }
        return storedKind(bookId: id, packageId: packageId)
    }

    /// Loại hiệu lực của một sách thuộc nguồn `target`: ghi đè của sách, không có thì loại của nguồn.
    func effectiveKind(of target: LegadoSourceRuntime.Target, bookId: String?) -> ExtensionContentKind {
        if let id = LegadoSourceRuntime.nonEmpty(bookId),
           let kind = storedKind(bookId: id, packageId: target.packageId) {
            return kind
        }
        return target.source.kind.contentKind
    }

    /// Giá trị thô → loại (spec §13.6, nhánh bitmask): `v ≥ 8` đọc bit `64` tranh, `32` audio, `128` tệp, `8` chữ (theo
    /// thứ tự đó); `v < 8` là hệ nhỏ `0` chữ, `1` audio, `2` tranh, `4` video, `3` không rõ (U54). `nil` = bỏ qua.
    func contentKind(rawType value: Int) -> ExtensionContentKind? {
        switch value {
        case 0:
            return .text
        case 2:
            return .comic
        case 4:
            return .video
        case 8...:
            if value & 64 != 0 { return .comic }
            if value & 32 != 0 || value & 128 != 0 { break }
            if value & 8 != 0 { return .text }
        default:
            break
        }
        noteIgnored(value)
        return nil
    }

    // MARK: - Nội bộ

    private func storedKind(bookId: String, packageId: String) -> ExtensionContentKind? {
        let state = LegadoBookStateStore.shared.state(packageId: packageId, bookUrl: nil, bookId: bookId)
        guard let raw = state.typeOverride else { return nil }
        return contentKind(rawType: raw)
    }

    private func noteIgnored(_ value: Int) {
        lock.lock()
        let isFirst = loggedValues.insert(value).inserted
        lock.unlock()
        guard isFirst else { return }
        AppLogger.shared.log("📚 [LegadoBookType] Bỏ qua book.type = \(value) (audio/tệp/chưa rõ) — dùng loại của nguồn")
    }
}
