import Foundation

/// **Tạm thời** (1.3.1026) — một biến thể của màn tự thử nhịp dọc header (`HeaderSpacingLabView`): kiểu nội dung × cách
/// chỉnh khoảng trên. Anh Bửu chọn mốc B ("đáy thanh +16") rồi duyệt bản đo; số đo từ máy quyết định cách áp cho mọi màn.
/// Gỡ cả thư mục `HeaderSpacingLab/` khi đã áp xong.
struct HeaderSpacingLabVariant: Identifiable, Hashable {
    enum Kind: String {
        case form = "Form không tiêu đề nhóm"
        case formHeader = "Form có tiêu đề nhóm"
        case formSearch = "Form dưới ô tìm"
        case plain = "List trơn"
        case plainSearch = "List trơn dưới ô tìm"
        case panels = "Panel ScrollView"
        case customBack = "Header tự dựng"
    }

    enum Fix: String {
        case none = "mặc định"
        case margin0 = "contentMargins top 0"
        case margin16 = "contentMargins top 16"
        case minHeader0 = "defaultMinListHeaderHeight 0"
        case compact = "listSectionSpacing compact"
        case margin16MinHeader0 = "contentMargins 16 + minHeader 0"
        case panelPad16 = "đệm trên 16"
    }

    let kind: Kind
    let fix: Fix

    var id: String { "\(kind)-\(fix)" }
    var hasSearch: Bool { kind == .formSearch || kind == .plainSearch }
    var isForm: Bool { kind == .form || kind == .formHeader || kind == .formSearch }
    var label: String { "\(kind.rawValue) · \(fix.rawValue)" }

    /// Thứ tự chạy. Form thử đủ cách vì khoảng 35pt nằm ở đâu trong UIKit chưa rõ; List trơn / panel chỉ cần mặc định và
    /// cách đích; trang header tự dựng đo mũi back chung so với mũi back hệ thống.
    static let all: [HeaderSpacingLabVariant] = {
        var list: [HeaderSpacingLabVariant] = []
        for fix: Fix in [.none, .margin0, .margin16, .minHeader0, .compact, .margin16MinHeader0] {
            list.append(.init(kind: .form, fix: fix))
        }
        for fix: Fix in [.none, .margin0, .margin16, .minHeader0, .compact] {
            list.append(.init(kind: .formHeader, fix: fix))
        }
        for fix: Fix in [.none, .margin0, .margin16, .minHeader0] {
            list.append(.init(kind: .formSearch, fix: fix))
        }
        for kind: Kind in [.plain, .plainSearch] {
            list.append(.init(kind: kind, fix: .none))
            list.append(.init(kind: kind, fix: .margin16))
        }
        list.append(.init(kind: .panels, fix: .none))
        list.append(.init(kind: .panels, fix: .panelPad16))
        list.append(.init(kind: .customBack, fix: .none))
        return list
    }()
}
