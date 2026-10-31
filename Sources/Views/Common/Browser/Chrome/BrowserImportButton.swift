import SwiftUI

/// Nút **Import truyện** trong thanh dưới của trình duyệt (mockup 2026-10-31, thay viên Import nổi): icon tiện ích đầu
/// tiên khớp URL trang (`ExtensionUrlMatcher.matches`); ≥ 2 nguồn ⇒ thêm số nguồn ở góc.
///
/// - Chạm: 1 nguồn ⇒ import luôn; ≥ 2 ⇒ bảng chọn nguồn bật ngay trên nút (`BrowserImportSourcePicker`), nút sáng kiểu
///   chip "on" trong lúc bảng mở. Mở bảng từ chỗ khác (ngăn kéo "…") thì gán `isPickerPresented`.
/// - Chọn nguồn trong bảng ⇒ đóng bảng trước, import chạy **sau** khi popover đóng hẳn: import đóng luôn cả trình duyệt,
///   đóng màn trình bày trong lúc popover còn đang đóng thì UIKit có thể bỏ qua lặng lẽ.
///
/// View cha chỉ dựng nút khi có ít nhất một nguồn khớp.
struct BrowserImportButton: View {
    let matches: [ExtensionUrlMatcher.Match]
    @Binding var isPickerPresented: Bool
    let onImport: (ExtensionUrlMatcher.Match) -> Void

    @State private var chosenMatch: ExtensionUrlMatcher.Match? = nil

    private static let iconSize: CGFloat = 24

    var body: some View {
        Button(action: handleTap) {
            icon
                .frame(width: 38, height: 38)
                .background {
                    if isPickerPresented {
                        Circle().fill(Color.white.opacity(0.18))
                        Circle().strokeBorder(Color.white.opacity(0.6), lineWidth: 1)
                    }
                }
                .overlay(alignment: .topTrailing) { countBadge }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
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

    @ViewBuilder
    private var icon: some View {
        if let first = matches.first {
            ExtensionIconView(localPath: first.ext.localPath, iconUrl: first.ext.iconUrl, size: Self.iconSize)
        }
    }

    @ViewBuilder
    private var countBadge: some View {
        if matches.count > 1 {
            Text("\(matches.count)")
                .font(.system(size: 10.5, weight: .bold))
                .foregroundColor(.black)
                .padding(.horizontal, 4)
                .frame(minWidth: 15, minHeight: 15)
                .background(Capsule().fill(Color.white))
                .accessibilityHidden(true)
        }
    }

    private var label: String {
        matches.count == 1 ? "Import truyện" : "Import · \(matches.count) nguồn"
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
