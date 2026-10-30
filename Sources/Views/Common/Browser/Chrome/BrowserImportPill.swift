import SwiftUI

/// Viên **Import truyện** nổi trong suốt góc phải, ngay trên thanh kính dưới (mockup 2026-10-30, màn "Mới 1", "Mới 1b").
///
/// - Mang icon các tiện ích khớp URL trang (`ExtensionUrlMatcher.matches`): tối đa 2 icon chồng nhau + chip "+K".
/// - Chữ: 1 nguồn ⇒ "Import truyện", ≥ 2 ⇒ "Import · N nguồn". Trang cuộn xuống (`isCollapsed`) ⇒ chỉ còn cụm icon, cuộn
///   lên hiện đủ chữ — hiệu ứng chỉ làm mờ **chữ**, nền kính luôn hiện 100% (xem `BrowserGlassCapsuleBackground`).
/// - Chạm: 1 nguồn ⇒ import luôn; ≥ 2 ⇒ bảng chọn nguồn bật ngay trên viên (`BrowserImportSourcePicker`). Mở bảng từ
///   chỗ khác (ngăn kéo "…") thì gán `isPickerPresented`.
/// - Chọn nguồn trong bảng ⇒ đóng bảng trước, import chạy **sau** khi popover đóng hẳn: import đóng luôn cả trình duyệt,
///   đóng màn trình bày trong lúc popover còn đang đóng thì UIKit có thể bỏ qua lặng lẽ.
///
/// View cha chỉ dựng viên khi có ít nhất một nguồn khớp và có `onImport`.
struct BrowserImportPill: View {
    let matches: [ExtensionUrlMatcher.Match]
    let isCollapsed: Bool
    @Binding var isPickerPresented: Bool
    let onImport: (ExtensionUrlMatcher.Match) -> Void

    @State private var chosenMatch: ExtensionUrlMatcher.Match? = nil

    private static let iconSize: CGFloat = 30
    private static let maxStackedIcons = 2
    /// Cùng bo góc với `ExtensionIconView` (18% cạnh) để viền khít ảnh icon.
    private static let iconCorner: CGFloat = iconSize * 0.18
    private static let iconBorderColor = Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255).opacity(0.95)
    private static let moreChipColor = Color(red: 58 / 255, green: 58 / 255, blue: 60 / 255)

    var body: some View {
        Button(action: handleTap) {
            HStack(spacing: 9) {
                iconStack
                if !isCollapsed {
                    Text(label)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .fixedSize()
                        .transition(.opacity)
                }
            }
            .padding(.leading, 6)
            .padding(.trailing, isCollapsed ? 6 : 15)
            .frame(height: 42)
            .background {
                BrowserGlassCapsuleBackground(outlineOpacity: 0.24, isHighlighted: isPickerPresented)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.22), value: isCollapsed)
        .accessibilityLabel(label)
        .popover(isPresented: $isPickerPresented, arrowEdge: .bottom) {
            BrowserImportSourcePicker(matches: matches) { match in
                chosenMatch = match
                isPickerPresented = false
            }
            .presentationCompactAdaptation(.popover)
            .preferredColorScheme(.dark)
        }
        .onChange(of: isPickerPresented) { _, isShowing in
            guard !isShowing, let match = chosenMatch else { return }
            chosenMatch = nil
            // Chờ hoạt ảnh đóng popover xong (như độ trễ 0,35 s của bảng khiên).
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                onImport(match)
            }
        }
    }

    private var label: String {
        matches.count == 1 ? "Import truyện" : "Import · \(matches.count) nguồn"
    }

    private var extraCount: Int {
        max(0, matches.count - Self.maxStackedIcons)
    }

    private var iconStack: some View {
        HStack(spacing: -9) {
            ForEach(matches.prefix(Self.maxStackedIcons)) { match in
                ExtensionIconView(localPath: match.ext.localPath, iconUrl: match.ext.iconUrl, size: Self.iconSize)
                    .overlay(iconBorder)
            }
            if extraCount > 0 {
                Text("+\(extraCount)")
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundColor(Color.white.opacity(0.85))
                    .frame(width: Self.iconSize, height: Self.iconSize)
                    .background(Self.moreChipColor, in: RoundedRectangle(cornerRadius: Self.iconCorner))
                    .overlay(iconBorder)
            }
        }
        .accessibilityHidden(true)
    }

    private var iconBorder: some View {
        RoundedRectangle(cornerRadius: Self.iconCorner)
            .strokeBorder(Self.iconBorderColor, lineWidth: 1.5)
    }

    private func handleTap() {
        guard let first = matches.first else { return }
        if matches.count == 1 {
            onImport(first)
        } else {
            isPickerPresented = true
        }
    }
}
