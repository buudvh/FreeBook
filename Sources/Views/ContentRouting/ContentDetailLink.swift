import SwiftUI

/// Thay cho `NavigationLink(destination: BookDetailView(...))` của một item danh sách: nguồn video / âm thanh ⇒ **nút** mở
/// màn xem phim / màn nghe (`ContentDetailRouter`), loại khác ⇒ `NavigationLink` tới `BookDetailView` y như cũ. Kiểu nút
/// (`.buttonStyle`) gắn ở ngoài áp cho cả hai nhánh.
struct ContentDetailLink<Label: View>: View {
    let item: ExtensionItemResult
    let packageId: String
    let sourceName: String
    /// `bookId` chỗ gọi vẫn truyền cho `BookDetailView` (giữ đúng dạng cũ của từng màn); phim / âm thanh không dùng.
    let detailBookId: String
    @ViewBuilder let label: () -> Label

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        if ContentDetailRouter.opensPlayer(packageId: packageId) {
            Button {
                ContentDetailRouter.openIfVideo(item, packageId: packageId, sourceName: sourceName, modelContainer: modelContext.container)
            } label: {
                label()
            }
        } else {
            NavigationLink(destination: BookDetailView(
                bookId: detailBookId,
                extensionPackageId: packageId,
                initialDetailUrl: item.link,
                sourceName: sourceName,
                initialHost: item.host
            )) {
                label()
            }
        }
    }
}
