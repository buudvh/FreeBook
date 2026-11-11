import SwiftUI

/// **Nền kính cho mọi sheet / popup** của app (1.3.873, anh Bửu: "sửa nền các loại sheet như các sheet gần đây", "như hub,
/// nút + kệ sách", "mấy pop up như bật tắt dịch cũng vậy"): cùng kiểu sheet hub / sheet nghe — nền
/// `DrawerGlassSheetBackground` (Độ trong suốt + Độ đục của **Menu ba chấm**, đục thấp nhất 20%), sheet bo 16, nội dung
/// tông tối, nền danh sách ẩn để thấy kính, **ô danh sách mờ** như dòng của sheet hub (`rowFill`).
///
/// - Sheet: `.appGlassSheet()` gắn ở chỗ trình bày (`.sheet { … }`) — bọc nội dung sheet. Popup: `.appGlassPopover()`
///   trong nội dung `.popover` (popup không chỉnh được bo góc).
/// - Ô mờ: `List` / `Form` bọc nội dung bằng `Group { … }.glassSheetRows()` — chỉ có tác dụng khi nằm trong sheet / popup kính
///   (`isGlassSheet` của environment), nên trang thường dùng chung view vẫn như cũ. Ô tự đặt `listRowBackground` riêng
///   (dòng đang chọn…) thắng vì gần ô hơn.
/// - Không dùng cho: sheet chia sẻ / chọn file của hệ thống, bảng của Reader và truyện tranh (theo nền đọc), sheet đã có
///   nền riêng (`presentationBackground`).
struct AppGlassSheetModifier: ViewModifier {
    enum Kind {
        case sheet
        case popover
        /// Sheet trình bày bằng UIKit (`UIHostingController` + `.pageSheet`): `presentationBackground` không tới được ⇒ kính
        /// vẽ bằng `.background`; người trình bày đặt `view.backgroundColor = .clear` + `preferredCornerRadius = 16`.
        case uikitSheet
    }

    let kind: Kind

    /// Nền ô danh sách trong sheet kính — cùng màu dòng của sheet hub (`hubSheetPanelRow`).
    static let rowFill = Color.primary.opacity(0.08)

    @ViewBuilder
    func body(content: Content) -> some View {
        let styled = content
            .scrollContentBackground(.hidden)
            .environment(\.isGlassSheet, true)
            .preferredColorScheme(.dark)
        switch kind {
        case .sheet:
            styled
                .presentationBackground { DrawerGlassSheetBackground() }
                .presentationCornerRadius(16)
        case .popover:
            styled.presentationBackground { DrawerGlassSheetBackground() }
        case .uikitSheet:
            styled.background { DrawerGlassSheetBackground() }
        }
    }

    /// Khoá environment lồng trong type (một type chính mỗi file).
    struct GlassKey: EnvironmentKey {
        static var defaultValue: Bool { false }
    }

    /// Ô danh sách mờ khi nằm trong sheet kính; ngoài sheet kính ⇒ nền ô mặc định.
    struct Rows: ViewModifier {
        @Environment(\.isGlassSheet) private var isGlassSheet

        func body(content: Content) -> some View {
            let fill: Color? = isGlassSheet ? AppGlassSheetModifier.rowFill : nil
            return content.listRowBackground(fill)
        }
    }

    /// Nền đặc của một dải / trang (vd thanh tìm của `SearchView`) — trong sheet kính thì trong suốt để thấy kính.
    struct SolidBackground: View {
        let color: Color
        @Environment(\.isGlassSheet) private var isGlassSheet

        var body: some View {
            isGlassSheet ? Color.clear : color
        }
    }
}

extension EnvironmentValues {
    /// Đang nằm trong sheet / popup kính (`AppGlassSheetModifier`).
    var isGlassSheet: Bool {
        get { self[AppGlassSheetModifier.GlassKey.self] }
        set { self[AppGlassSheetModifier.GlassKey.self] = newValue }
    }
}

extension View {
    /// Nền kính cho sheet (gắn bọc nội dung `.sheet { … }`) — xem `AppGlassSheetModifier`.
    func appGlassSheet() -> some View {
        modifier(AppGlassSheetModifier(kind: .sheet))
    }

    /// Nền kính cho sheet trình bày bằng UIKit (gốc của `UIHostingController`; xem `Kind.uikitSheet`).
    func appGlassUIKitSheet() -> some View {
        modifier(AppGlassSheetModifier(kind: .uikitSheet))
    }

    /// Nền kính cho popup (`.popover { … }`).
    func appGlassPopover() -> some View {
        modifier(AppGlassSheetModifier(kind: .popover))
    }

    /// Nền đặc `color`, trừ khi nằm trong sheet kính (khi đó trong suốt).
    func glassAwareBackground(_ color: Color) -> some View {
        background(AppGlassSheetModifier.SolidBackground(color: color))
    }

    /// Ô mờ cho mọi dòng của một `List` / `Form` (gắn lên `Group` bọc nội dung danh sách) khi nằm trong sheet kính.
    func glassSheetRows() -> some View {
        modifier(AppGlassSheetModifier.Rows())
    }
}
