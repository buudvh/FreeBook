import SwiftUI

/// Nút chọn **một** loại nội dung dạng menu (Tất cả · Truyện chữ · Truyện tranh · Phim), đứng cạnh ô tìm viên thuốc —
/// thay hàng chip `ExtensionKindFilterBar` ở ngăn kéo chọn nguồn (kéo cuộn hàng chip tranh với vuốt đóng ngăn kéo).
/// Viên thuốc cao 40 bằng ô tìm: icon + tên loại đang chọn + ↕; mục đang chọn trong menu có ✓.
///
/// Lựa chọn cùng quy ước với `ExtensionKindFilterBar`: `""` = tất cả, còn lại `ExtensionContentKind.rawValue`.
struct ExtensionKindMenuButton: View {
    @Binding var selection: String
    /// Gọi sau mỗi lần chọn (ngăn kéo cần `refreshContent()` để vẽ lại).
    var onChange: () -> Void = {}

    private static let allSymbol = "square.grid.2x2"

    private var selectedKind: ExtensionContentKind? {
        SearchExtensionScopePolicy.selectedKind(selection)
    }

    var body: some View {
        Menu {
            option(title: "Tất cả", symbol: Self.allSymbol, isSelected: selectedKind == nil, value: "")
            ForEach(SearchExtensionScopePolicy.browsableKinds, id: \.self) { kind in
                option(title: Self.title(of: kind), symbol: kind.symbolName, isSelected: selectedKind == kind, value: kind.rawValue)
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: selectedKind?.symbolName ?? Self.allSymbol)
                    .font(.system(size: 13, weight: .semibold))
                Text(selectedKind.map(Self.title(of:)) ?? "Tất cả")
                    .font(.subheadline)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.secondary)
            }
            .foregroundColor(.primary)
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(Color(.tertiarySystemFill), in: Capsule())
            .contentShape(Capsule())
        }
        .accessibilityLabel("Loại nội dung: \(selectedKind.map(Self.title(of:)) ?? "Tất cả")")
    }

    private func option(title: String, symbol: String, isSelected: Bool, value: String) -> some View {
        Button(action: {
            selection = value
            onChange()
        }) {
            if isSelected {
                Label(title, systemImage: "checkmark")
            } else {
                Label(title, systemImage: symbol)
            }
        }
    }

    /// Nhãn gọn cho menu: phim dùng "Phim" (nhãn nhóm của kho là "Phim/Video").
    private static func title(of kind: ExtensionContentKind) -> String {
        kind == .video ? "Phim" : kind.label
    }
}
