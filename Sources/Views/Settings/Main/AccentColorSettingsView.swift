import SwiftUI

/// Cài đặt → Chung → Giao diện → **Màu nhấn** (1.3.678, theo mockup đã duyệt): bốn màu `AppAccentColor` (mặc định
/// Xanh ngọc, không còn trắng) và ô xem trước nền tối + nền sáng dựng bằng thành phần thật — công tắc, nút đặc
/// `.appFilled`, chip đang chọn kiểu `ExtensionKindFilterBar`, vòng xoay, link, icon header, tab đang chọn.
///
/// Chạm một màu là ghi `@AppStorage` ⇒ màn này, cả app (`.appAccentTint()`) và phần UIKit (`MainTabView` →
/// `applyToWindows()`) đổi ngay, không cần mở lại app.
struct AccentColorSettingsView: View {
    @AppStorage(AppAccentColor.storageKey) private var storedAccent = AppAccentColor.defaultValue.rawValue
    @State private var previewToggleOn = true

    var body: some View {
        let selected = AppAccentColor(storedValue: storedAccent)
        Form { Group {
            Section {
                ForEach(AppAccentColor.allCases) { accent in
                    optionRow(accent, isSelected: accent == selected)
                }
            }

            Section {
                preview(accent: selected, scheme: .dark)
                preview(accent: selected, scheme: .light)
            } header: {
                Text("Xem trước")
            }
        }.glassSheetRows() }
        .backPageTitle("Màu nhấn")
    }

    // MARK: - Lựa chọn

    private func optionRow(_ accent: AppAccentColor, isSelected: Bool) -> some View {
        Button {
            storedAccent = accent.rawValue
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .fill(accent.color)
                    .frame(width: 16, height: 16)
                Text(accent.title)
                    .foregroundStyle(.primary)
                if accent == AppAccentColor.defaultValue {
                    Text("· mặc định")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(accent.color)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Xem trước

    /// Một khung xem trước ở `scheme`: nền và mọi màu hệ thống bên trong tự đổi theo nền tối / sáng.
    private func preview(accent: AppAccentColor, scheme: ColorScheme) -> some View {
        FlowLayout(spacing: 12) {
            Toggle("Công tắc", isOn: $previewToggleOn)
                .labelsHidden()
                .toggleStyle(.switch)
            Button("Lưu") {}
                .buttonStyle(.appFilled(accent.color, fullWidth: false))
            previewChip(accent)
            ProgressView()
            Text("Mở link lỗi")
                .font(.subheadline)
                .underline()
                .foregroundStyle(accent.color)
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(accent.color)
            previewTabItem(MainTabBar.items[0].systemImage, MainTabBar.items[0].title, color: accent.color)
            previewTabItem(MainTabBar.items[1].systemImage, MainTabBar.items[1].title, color: Color(uiColor: .systemGray))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .tint(accent.color)
        .environment(\.colorScheme, scheme)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(scheme == .dark ? "Xem trước trên nền tối" : "Xem trước trên nền sáng")
    }

    /// Cùng kiểu chip đang chọn của `ExtensionKindFilterBar`: chữ màu nhấn, nền nhấn 18%, viền 60%.
    private func previewChip(_ accent: AppAccentColor) -> some View {
        Text("Truyện chữ")
            .font(.subheadline)
            .padding(.horizontal, 12)
            .frame(minHeight: 32)
            .foregroundStyle(accent.color)
            .background(accent.color.opacity(0.18), in: Capsule())
            .overlay(Capsule().stroke(accent.color.opacity(0.6), lineWidth: 1))
    }

    /// Ô tab của `MainTabBar` (icon 21pt + chữ 10pt).
    private func previewTabItem(_ systemImage: String, _ title: String, color: Color) -> some View {
        VStack(spacing: 3) {
            Image(systemName: systemImage)
                .font(.system(size: 21))
            Text(title)
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(color)
    }
}
