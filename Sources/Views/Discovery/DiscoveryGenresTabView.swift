import SwiftUI

/// Tab hiển thị lưới danh sách Thể loại trong trang Khám Phá. Đầu lưới là ô tìm viên thuốc kiểu mục lục
/// (`ChapterTOCSearchField`): lọc ngay khi gõ, khớp cả tiêu đề gốc lẫn tiêu đề đã dịch, không phân biệt hoa thường/dấu.
struct DiscoveryGenresTabView: View {
    let genreItems: [CategoryResult]
    let homeItems: [CategoryResult]
    /// Phồn → giản + dịch của nguồn (`ChineseTextPipeline.sourceOptions`), `DiscoveryView` tính một lần.
    let textOptions: ChineseTextPipeline.Options
    @Binding var selectedCategoryId: String
    let onSelectGenre: (CategoryResult) -> Void
    /// Nguồn Legado đang xem ⇒ tab vẽ mục khám phá có kiểu (tiêu đề nhóm, ô bấm, điều khiển — `LegadoExploreTabView`)
    /// thay cho lưới `genreItems`.
    var legadoExtension: Extension? = nil

    @State private var searchText = ""
    /// Tiêu đề đã dịch theo `CategoryResult.id` — dựng một lần khi bắt đầu tìm (không dịch lại mỗi phím gõ); danh sách
    /// hoặc cấu hình dịch / phồn → giản đổi thì bỏ.
    @State private var translatedTitles: [String: String] = [:]

    private var filteredItems: [CategoryResult] {
        let query = Self.searchKey(searchText.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !query.isEmpty else { return genreItems }
        return genreItems.filter { item in
            Self.searchKey(item.title).contains(query)
                || Self.searchKey(translatedTitles[item.id] ?? translateIfNeeded(item.title)).contains(query)
        }
    }

    var body: some View {
        if let legadoExtension {
            LegadoExploreTabView(
                localPath: legadoExtension.localPath,
                packageId: legadoExtension.packageId,
                textOptions: textOptions,
                onSelectGenre: onSelectGenre
            )
            // Sửa JSON nguồn ⇒ phiên bản đổi ⇒ dựng lại tab (không giữ mục khám phá của JSON cũ).
            .id("\(legadoExtension.packageId)#\(legadoExtension.version)")
        } else {
            genreGrid
        }
    }

    private var genreGrid: some View {
        ScrollView {
            if genreItems.isEmpty {
                Text("Nguồn truyện này không có danh sách thể loại cụ thể.")
                    .foregroundColor(.secondary)
                    .padding(.top, 40)
            } else {
                VStack(spacing: 0) {
                    ChapterTOCSearchField(
                        text: $searchText,
                        placeholder: "Tìm kiếm \(genreItems.count) thể loại",
                        palette: .system
                    )
                    .padding(.leading, 16)
                    .padding(.trailing, 10)
                    .padding(.top, 12)

                    let items = filteredItems
                    if items.isEmpty {
                        Text("Không có thể loại nào khớp")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding(.top, 24)
                    }
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(items) { item in
                            Button(action: {
                                if homeItems.contains(where: { $0.id == item.id }) {
                                    selectedCategoryId = item.id
                                } else {
                                    onSelectGenre(item)
                                }
                            }) {
                                Text(translatedTitles[item.id] ?? translateIfNeeded(item.title))
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .padding(.horizontal, 4)
                                    .frame(height: 50)
                                    .background(Color.white.opacity(0.12))
                                    .foregroundColor(.white)
                                    .cornerRadius(10)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(Color.white.opacity(0.25), lineWidth: 1)
                                    )
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: searchText) { _, text in
            if !text.isEmpty && translatedTitles.isEmpty { rebuildTranslatedTitles() }
        }
        .onChange(of: genreItems.map(\.id)) { _, _ in translatedTitles = [:] }
        .onChange(of: textOptions) { _, _ in translatedTitles = [:] }
    }

    private func rebuildTranslatedTitles() {
        var titles: [String: String] = [:]
        for item in genreItems {
            titles[item.id] = translateIfNeeded(item.title)
        }
        translatedTitles = titles
    }

    /// Khoá so khớp: bỏ dấu, không phân biệt hoa thường, "đ" ≈ "d" — gõ "he thong" vẫn ra "Hệ Thống Lưu".
    private static func searchKey(_ text: String) -> String {
        text.replacingOccurrences(of: "đ", with: "d")
            .replacingOccurrences(of: "Đ", with: "D")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    private func translateIfNeeded(_ text: String) -> String {
        ChineseTextPipeline.meta(text, textOptions)
    }
}
