import SwiftUI

/// Cụm **R | C** (Riêng truyện | Chung) đặt cuối hàng aa…AA của màn Sửa từ chế độ danh sách
/// (`DictEntryEditListMode.caseRowTrailing`) — hậu tố / tiền tố của lọc name local mở từ một truyện (2026-11-28, mockup
/// https://claude.ai/artifact/JwiiU3XFYTk7Rz1hAMS7G2 khung M5 / M5b / N3). Chép **kiểu** cụm R | C của panel Dịch Reader
/// (`ReaderDefinitionOverlayView.dictSegmentButton`: nút rộng cố định 30 pt, chữ 13 pt, nền nhóm xám mờ bo 6, nút đang chọn
/// nền xám đậm hơn, ghim cam `CoverPinBadge` nhô ở góc trên phải) nhưng chữ theo màu hệ thống (panel Reader tô theo nền đọc)
/// — nút của Reader là hàm của view đó, gắn `selectedTheme` nên không dùng lại trực tiếp được.
///
/// **Ghim mặc định** (N3, anh Bửu duyệt): nhấn giữ R hoặc C ⇒ ghim nút đó + toast như panel Dịch, nhấn giữ nút đang ghim ⇒ bỏ
/// ghim. Khi **thêm mới** (`selectsOnPin`) ghim xong chọn luôn nút đó; khi **sửa mục có sẵn** nhấn giữ **chỉ ghim**, không đổi
/// phạm vi của mục (session chính chốt 2026-11-28: đổi phạm vi chỉ bằng chạm, vì R → C ghi đè Chung). Nhớ bằng `@AppStorage` khoá `localNameFilterAffixScopePin` ("" chưa ghim / "book" / "common") —
/// chung cho mọi lần mở. Ghim chỉ quyết định phạm vi chọn sẵn khi **thêm từ chip "+ X" / "+ Thêm …" ở màn Sửa từ của màn
/// duyệt** (`defaultIsBookScope`, chưa ghim ⇒ R); "+ Thêm" trong nhóm của màn Quản lý theo nhóm, màn danh sách theo chip
/// phạm vi, sửa mục có sẵn theo phạm vi của mục.
struct DictEntryEditScopeToggle: View {
    /// Khoá `@AppStorage` của ghim (chữ thường, không dấu chấm ⇒ Backup tự gói).
    static let pinStorageKey = "localNameFilterAffixScopePin"

    /// `true` = R (Riêng truyện), `false` = C (Chung).
    @Binding var isBookScope: Bool
    /// `true` (thêm mới) ⇒ ghim xong chọn luôn nút vừa ghim; `false` (sửa mục có sẵn) ⇒ chỉ ghim, phạm vi giữ nguyên.
    var selectsOnPin: Bool = true

    /// "" = chưa ghim, "book" = ghim R, "common" = ghim C.
    // Chuỗi trần = `pinStorageKey` (đặt thẳng trong thuộc tính bọc cho chắc).
    @AppStorage("localNameFilterAffixScopePin") private var pinnedRaw: String = ""

    private static let buttonWidth: CGFloat = 30

    /// Nút đang ghim: `true` = R, `false` = C, `nil` = chưa ghim.
    static func pinnedIsBookScope(_ raw: String) -> Bool? {
        switch raw {
        case "book": return true
        case "common": return false
        default: return nil
        }
    }

    /// Phạm vi chọn sẵn khi thêm từ chip ở màn Sửa từ của màn duyệt: nút đang ghim, chưa ghim ⇒ R.
    static var defaultIsBookScope: Bool {
        pinnedIsBookScope(UserDefaults.standard.string(forKey: pinStorageKey) ?? "") ?? true
    }

    var body: some View {
        let pinned = Self.pinnedIsBookScope(pinnedRaw)
        HStack(spacing: 0) {
            segment("R", isSelected: isBookScope, isPinned: pinned == true, accessibility: "Riêng truyện") {
                isBookScope = true
            } onPin: {
                togglePin(book: true, current: pinned)
            }
            Divider()
                .frame(height: 14)
            segment("C", isSelected: !isBookScope, isPinned: pinned == false, accessibility: "Chung mọi truyện") {
                isBookScope = false
            } onPin: {
                togglePin(book: false, current: pinned)
            }
        }
        .padding(2)
        // Nền bo góc thay cho cắt cả nhóm: ghim nhô ra ngoài nhóm, không được bị cắt (như panel Dịch).
        .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Phạm vi lưu")
    }

    /// Nhấn giữ: nút đang ghim ⇒ bỏ ghim; nút khác ⇒ ghim nút đó, thêm mới thì chọn luôn (như `onPinScope` của panel Dịch),
    /// sửa mục có sẵn thì không đổi lựa chọn.
    private func togglePin(book: Bool, current: Bool?) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let label = book ? "Riêng" : "Chung"
        if current == book {
            pinnedRaw = ""
            ToastManager.shared.show(message: "Đã bỏ ghim Phạm vi: \(label) — thêm mới về mặc định Riêng", type: .success)
        } else {
            pinnedRaw = book ? "book" : "common"
            if selectsOnPin { isBookScope = book }
            ToastManager.shared.show(message: "Đã ghim mặc định Phạm vi: \(label)", type: .success)
        }
    }

    private func segment(
        _ title: String,
        isSelected: Bool,
        isPinned: Bool,
        accessibility: String,
        action: @escaping () -> Void,
        onPin: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(verbatim: title)
                .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                .foregroundColor(isSelected ? .primary : .secondary)
                .frame(width: Self.buttonWidth)
                .padding(.vertical, 6)
                .background(isSelected ? Color.secondary.opacity(0.25) : Color.clear)
                .cornerRadius(6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibility)
        .accessibilityValue(isPinned ? "Đang ghim mặc định" : "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityAction(named: Text(isPinned ? "Bỏ ghim mặc định" : "Ghim mặc định"), onPin)
        // Ghim kiểu bìa Kệ ở góc trên phải, nhô ra ngoài nút; nút thứ hai vẽ sau ⇒ nâng `zIndex` để nền "đang chọn" của nó
        // không phủ lên ghim của nút đầu (như `dictSegmentButton`).
        .overlay(alignment: .topTrailing) {
            if isPinned {
                CoverPinBadge(diameter: 15, angle: 20, accessibilityText: "Đang ghim mặc định")
                    .offset(x: 5, y: -7)
                    .accessibilityHidden(true)
            }
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.4).onEnded { _ in onPin() }
        )
        .zIndex(isPinned ? 1 : 0)
    }
}
