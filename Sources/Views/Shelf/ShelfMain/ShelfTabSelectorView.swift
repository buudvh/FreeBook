import SwiftUI

/// Thanh chọn tab của Kệ sách: **hàng nút rời**, không phải `Picker(.segmented)`.
///
/// Lý do đổi: segmented control chia đều chiều ngang cho cả 4 tab, nên Downloads và Bộ Sưu Tập chiếm
/// đúng bằng Kệ Sách và Lịch Sử dù chữ dài và ít được bấm. Hai tab đó nay là nút icon 40×40
/// (`ShelfTab.isIconOnly`), hai tab còn lại là pill chữ co theo nội dung.
///
/// Không đổi gì ở `TabView`/`.tag()` bên dưới: `selection` vẫn là `ShelfTab` nên đường điều hướng từ
/// `SearchView` (`userInfo["shelfTab"]`) và từ `ShelfView+BookImport` chạy như cũ.
///
/// Dùng màu semantic (`accentColor`, `.secondarySystemBackground`) chứ không hardcode màu tối — app đi
/// theo giao diện hệ thống, không phải dark-only.
struct ShelfTabSelectorView: View {
    @Binding var selection: ShelfTab

    var body: some View {
        HStack(spacing: 8) {
            ForEach(ShelfTab.allCases) { tab in
                if let icon = tab.iconName {
                    iconButton(tab, systemImage: icon)
                } else {
                    pillButton(tab)
                }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Hai kiểu nút

    private func iconButton(_ tab: ShelfTab, systemImage: String) -> some View {
        Button {
            select(tab)
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .medium))
                .frame(width: 40, height: 40)
                .background(background(for: tab, shape: Circle()))
                .foregroundColor(foreground(for: tab))
        }
        .buttonStyle(.plain)
        // Nút icon không có chữ nên **bắt buộc** có nhãn, không thì VoiceOver đọc thành nút vô danh.
        .accessibilityLabel(tab.navigationTitle)
        .accessibilityAddTraits(selection == tab ? [.isButton, .isSelected] : [.isButton])
    }

    private func pillButton(_ tab: ShelfTab) -> some View {
        Button {
            select(tab)
        } label: {
            Text(tab.pickerTitle)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(background(for: tab, shape: Capsule()))
                .foregroundColor(foreground(for: tab))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selection == tab ? [.isButton, .isSelected] : [.isButton])
    }

    // MARK: - Trạng thái chọn

    private func select(_ tab: ShelfTab) {
        guard selection != tab else { return }
        withAnimation(.easeInOut(duration: 0.18)) {
            selection = tab
        }
    }

    private func background<S: InsettableShape>(for tab: ShelfTab, shape: S) -> some View {
        let isSelected = selection == tab
        return shape
            .fill(isSelected ? Color.accentColor.opacity(0.15) : Color(.secondarySystemBackground))
            .overlay(
                shape.strokeBorder(
                    isSelected ? Color.accentColor : Color.secondary.opacity(0.25),
                    lineWidth: isSelected ? 1.5 : 1
                )
            )
    }

    private func foreground(for tab: ShelfTab) -> Color {
        selection == tab ? .accentColor : .secondary
    }
}
