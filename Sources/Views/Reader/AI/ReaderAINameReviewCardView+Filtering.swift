import SwiftUI

/// Ô tìm + "phần đang hiện" của thẻ duyệt name (`ReaderAINameReviewCardView`) — anh Bửu 2026-11-27 ("danh sách name kết
/// quả đang thiếu ô tìm kiếm"), plan `Docs/Plans/2026-11-27-nghia-ten-tay-huyen.md` mục 4, mockup
/// https://claude.ai/artifact/UjY2CA9eEaThdo96xSgoiz khung 2. Có ở **cả hai** luồng (lọc name local và AI).
///
/// - Mục đang hiện = khớp chip loại (chỉ luồng lọc local) **và** khớp ô tìm (chữ Hán hoặc nghĩa).
/// - "Chọn hết" / "Bỏ chọn" chỉ áp lên mục đang hiện (bỏ qua hàng gạch của luồng AI) — trước đây chip loại tính cả danh
///   sách.
/// - Ô tìm / chip **chỉ ẩn hàng**: số ở tiêu đề thẻ, số trên chip và nút Lưu của sheet vẫn tính trên cả `names`; Lưu lưu
///   mọi mục đang chọn, kể cả mục đang bị ẩn (`ReaderAINameReviewSheet.executeSave`).
extension ReaderAINameReviewCardView {
    private static let searchLocale = Locale(identifier: "vi_VN")

    /// Chuỗi đã chuẩn hoá để so (cùng luật `VoiceNameSearch.normalize`): `đ` → `d` (bỏ dấu của Foundation không đổi `đ`),
    /// bỏ dấu, không phân biệt hoa thường / độ rộng, gộp khoảng trắng. Gõ "klein" ra "Klein", "khac" ra "Khắc".
    static func searchKey(_ text: String) -> String {
        let folded = text
            .replacingOccurrences(of: "đ", with: "d")
            .replacingOccurrences(of: "Đ", with: "D")
            .folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: searchLocale)
        return folded.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Mục khớp ô tìm: chữ Hán chứa chuỗi gõ, hoặc nghĩa (`suggestedMeaning`) chứa chuỗi gõ. `query` đã qua `searchKey`.
    private static func matchesSearch(_ item: AIExtractedName, query: String) -> Bool {
        searchKey(item.original).contains(query) || searchKey(item.suggestedMeaning).contains(query)
    }

    /// `id` các mục đang hiện (chip loại ∩ ô tìm). `nil` ⇒ không lọc gì, mọi hàng hiện — ô tìm rỗng + chip "Tất cả" thì
    /// không phải chuẩn hoá chuỗi nào (tích / bỏ tích vẫn nhẹ). `activeFilter` = `activeCategoryFilter`, tính trên cả
    /// `names` chứ không trên kết quả tìm: tìm ra không mục nào của chip đang chọn ⇒ "Không có name khớp", không nhảy về
    /// "Tất cả".
    func visibleNameIDs(activeFilter: LocalNameFilter.Category?) -> Set<UUID>? {
        let query = Self.searchKey(searchText)
        guard activeFilter != nil || !query.isEmpty else { return nil }
        var ids = Set<UUID>()
        for item in names {
            if let activeFilter, LocalNameFilterCategoryBadge.category(forLabel: item.category) != activeFilter { continue }
            if !query.isEmpty, !Self.matchesSearch(item, query: query) { continue }
            ids.insert(item.id)
        }
        return ids
    }

    /// Chỉ số các hàng chọn được đang hiện (bỏ hàng gạch của luồng AI).
    private func selectableVisibleIndices(_ visible: Set<UUID>?) -> [Int] {
        let current = names
        return current.indices.filter { index in
            !isStruck(current[index]) && (visible?.contains(current[index].id) ?? true)
        }
    }

    /// Mọi hàng chọn được đang hiện đều đã chọn ⇒ nút hiện "Bỏ chọn". Không còn hàng nào (gạch hết / không khớp) ⇒
    /// "Chọn hết".
    func allSelected(visible: Set<UUID>?) -> Bool {
        let indices = selectableVisibleIndices(visible)
        let current = names
        return !indices.isEmpty && indices.allSatisfy { current[$0].isSelected }
    }

    /// "Chọn hết" / "Bỏ chọn": đổi các hàng chọn được **đang hiện**, ghi `names` một lần.
    func toggleSelectAll() {
        let indices = selectableVisibleIndices(visibleNameIDs(activeFilter: activeCategoryFilter))
        guard !indices.isEmpty else { return }
        var updated = names
        let target = !indices.allSatisfy { updated[$0].isSelected }
        for index in indices {
            updated[index].isSelected = target
        }
        names = updated
    }

    /// Ô tìm theo mockup khung 2 (cao 36, bo 10, nền ô tìm hệ thống) + nút ⓧ xoá chữ khi có chữ.
    var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.subheadline)
                .foregroundColor(.secondary)
            TextField("", text: $searchText, prompt: Text("Tìm chữ Hán hoặc nghĩa").foregroundColor(.secondary))
                .textFieldStyle(.plain)
                .font(.subheadline)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .accessibilityLabel("Tìm name")
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .frame(width: 28, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Xoá chữ tìm")
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, searchText.isEmpty ? 10 : 4)
        .frame(height: 36)
        .background(Color(UIColor.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))
    }

    /// Dòng báo khi ô tìm / chip không còn mục nào.
    var noMatchRow: some View {
        Text("Không có name khớp")
            .font(.subheadline)
            .foregroundColor(.secondary)
            .padding(.horizontal, 4)
            .padding(.vertical, 12)
    }
}
