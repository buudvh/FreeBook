import SwiftUI

/// Hàng chip chọn **một** loại nội dung: "Tất cả · Truyện chữ · Truyện tranh · Phim/Video".
///
/// Lựa chọn là chuỗi để gắn thẳng vào `@AppStorage`: `""` = tất cả, còn lại là `ExtensionContentKind.rawValue`
/// (luật đọc ở `SearchExtensionScopePolicy.selectedKind`). Nhãn dùng chung nhãn nhóm thể loại của kho
/// (`ExtensionContentKind.label`). Dùng ở `ExtensionSelectorView` (Khám phá) và `SearchView`.
struct ExtensionKindFilterBar: View {
    @Binding var selection: String

    private var selectedKind: ExtensionContentKind? {
        SearchExtensionScopePolicy.selectedKind(selection)
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(title: "Tất cả", symbol: nil, isSelected: selectedKind == nil) {
                    selection = ""
                }
                ForEach(SearchExtensionScopePolicy.browsableKinds, id: \.self) { kind in
                    chip(title: kind.label, symbol: kind.symbolName, isSelected: selectedKind == kind) {
                        selection = kind.rawValue
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
        }
    }

    private func chip(title: String, symbol: String?, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 12, weight: .semibold))
                }
                Text(title)
                    .font(.subheadline)
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 36)
            .foregroundColor(isSelected ? .accentColor : .primary)
            .background(isSelected ? Color.accentColor.opacity(0.18) : Color(.secondarySystemBackground))
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(isSelected ? Color.accentColor.opacity(0.6) : Color.white.opacity(0.12), lineWidth: 1)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
