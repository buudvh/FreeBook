import SwiftUI

/// Nút chọn **một** loại nội dung dạng menu (Tất cả · Truyện chữ · Truyện tranh · Phim), đứng cạnh ô tìm viên thuốc —
/// thay hàng chip `ExtensionKindFilterBar` ở ngăn kéo chọn nguồn (kéo cuộn hàng chip tranh với vuốt đóng ngăn kéo).
/// Nút tròn 40 × 40 (cao bằng ô tìm) **chỉ có icon** của loại đang chọn, icon 17pt nửa đậm như nút header — cỡ nút
/// không đổi theo độ dài tên loại (1.3.678). Tên loại nằm trong menu (mục đang chọn có ✓) và nhãn VoiceOver.
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
            Image(systemName: selectedKind?.symbolName ?? Self.allSymbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.primary)
                .frame(width: 40, height: 40)
                .background(Color(.tertiarySystemFill), in: Circle())
                .contentShape(Circle())
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
