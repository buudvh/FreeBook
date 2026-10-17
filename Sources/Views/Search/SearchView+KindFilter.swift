import SwiftUI

/// Công tắc "tất cả nguồn" + hàng chip loại nội dung của màn Tìm kiếm.
///
/// Tách khỏi `SearchView.swift` để file gốc không vượt baseline dòng (plan comic/video, A4). Luật lọc nằm ở
/// `SearchExtensionScopePolicy`; khi đang **đổi nguồn** hàng chip bị ẩn vì policy đã ép đúng loại của sách.
extension SearchView {
    @ViewBuilder
    var searchOptionsView: some View {
        Toggle(isOn: $searchAllSources) {
            Text("Tìm trên tất cả nguồn đã cài")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .toggleStyle(SwitchToggleStyle(tint: Color(white: 0.35)))
        .padding(.horizontal)
        .padding(.vertical, 6)

        if searchAllSources && changeSourceTargetBook == nil {
            ExtensionKindFilterBar(selection: $searchKindFilter)
                .onChange(of: searchKindFilter) { _, _ in
                    rerunSearchAfterKindChange()
                }
        }
    }

    /// Đổi chip sau khi đã tìm trên nhiều nguồn ⇒ tìm lại: nguồn vừa lọc vào chưa từng được tìm.
    func rerunSearchAfterKindChange() {
        guard searchAllSources, changeSourceTargetBook == nil, !sourceStates.isEmpty else { return }
        performSearch()
    }
}
