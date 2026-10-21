import SwiftUI

/// Tab hiển thị lưới danh sách Thể loại trong trang Khám Phá
struct DiscoveryGenresTabView: View {
    let genreItems: [CategoryResult]
    let homeItems: [CategoryResult]
    let isTranslationEnabled: Bool
    @Binding var selectedCategoryId: String
    let onSelectGenre: (CategoryResult) -> Void
    /// Nguồn Legado đang xem ⇒ tab vẽ mục khám phá có kiểu (tiêu đề nhóm, ô bấm, điều khiển — `LegadoExploreTabView`)
    /// thay cho lưới `genreItems`.
    var legadoExtension: Extension? = nil

    var body: some View {
        if let legadoExtension {
            LegadoExploreTabView(
                localPath: legadoExtension.localPath,
                packageId: legadoExtension.packageId,
                isTranslationEnabled: isTranslationEnabled,
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
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(genreItems) { item in
                        Button(action: {
                            if homeItems.contains(where: { $0.id == item.id }) {
                                selectedCategoryId = item.id
                            } else {
                                onSelectGenre(item)
                            }
                        }) {
                            Text(translateIfNeeded(item.title))
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

    private func translateIfNeeded(_ text: String) -> String {
        guard isTranslationEnabled && TranslateUtils.containsChinese(text) else {
            return text
        }
        return TranslateUtils.translateMeta(text)
    }
}
