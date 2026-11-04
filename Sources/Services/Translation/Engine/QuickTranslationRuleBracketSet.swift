import Foundation

/// Bản chụp **bất biến** của bộ ngoặc đang có hiệu lực cho một lượt dịch (1.3.692): chỉ gồm các cặp
/// đang bật, đã hạ xuống đơn vị UTF-16 để `QuickTranslationRuleMatcher` tra `<[>` / `<]>` trong O(1).
///
/// Dựng một lần cho mỗi lần đổi bộ ngoặc (`QuickTranslationRuleBracketStore` và
/// `QuickTranslationBookEngineConfigStore` giữ cache), **không** giải mã JSON theo từng dòng văn.
///
/// Dựng chịu lỗi: cặp mà một ô không đúng một đơn vị UTF-16, mở trùng đóng, hoặc dùng lại ký tự đã có ở
/// cặp đứng trước (ở bất kỳ vai nào) bị **bỏ qua** — dữ liệu sửa tay hay khôi phục từ bản cũ không được
/// làm một ký tự vừa là mở vừa là đóng.
public struct QuickTranslationRuleBracketSet: Sendable, Equatable {
    public let openUnits: Set<UInt16>
    public let closeUnits: Set<UInt16>
    private let closeByOpen: [UInt16: UInt16]

    /// Bộ ngoặc mặc định (`QuickTranslationRuleBracketDefaults.pairs`) — giá trị khi chưa ai sửa.
    public static let defaults = QuickTranslationRuleBracketSet(pairs: QuickTranslationRuleBracketDefaults.pairs)
    /// Không cặp nào bật ⇒ `<[>` / `<]>` không bao giờ khớp.
    public static let empty = QuickTranslationRuleBracketSet(pairs: [])

    public init(pairs: [QuickTranslationRuleBracketPair]) {
        var openUnits: Set<UInt16> = []
        var closeUnits: Set<UInt16> = []
        var closeByOpen: [UInt16: UInt16] = [:]
        for pair in pairs where pair.isEnabled {
            guard let open = QuickTranslationRuleBracketPair.singleUnit(of: pair.open),
                  let close = QuickTranslationRuleBracketPair.singleUnit(of: pair.close),
                  open != close else { continue }
            guard !openUnits.contains(open), !closeUnits.contains(open),
                  !openUnits.contains(close), !closeUnits.contains(close) else { continue }
            openUnits.insert(open)
            closeUnits.insert(close)
            closeByOpen[open] = close
        }
        self.openUnits = openUnits
        self.closeUnits = closeUnits
        self.closeByOpen = closeByOpen
    }

    public var isEmpty: Bool { closeByOpen.isEmpty }

    public func isOpen(_ unit: UInt16) -> Bool {
        openUnits.contains(unit)
    }

    public func isClose(_ unit: UInt16) -> Bool {
        closeUnits.contains(unit)
    }

    /// Ngoặc đóng đi cặp với `unit`; `nil` khi `unit` không phải ngoặc mở của bộ này.
    public func close(forOpen unit: UInt16) -> UInt16? {
        closeByOpen[unit]
    }
}
