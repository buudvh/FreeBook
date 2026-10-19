import SwiftUI

/// Section `banner`: carousel ảnh tràn ngang (16:9), vuốt chuyển trang và tự chuyển sau mỗi 5 giây.
///
/// Tỉ lệ cố định 16:9 bất kể `shape`: banner thường không khai `shape` (mặc định `book`) dù ảnh là ảnh ngang.
/// `TabView` kiểu trang nằm trong `overlay` của một khung có tỉ lệ cố định — đặt thẳng trong `ScrollView` dọc thì nó
/// không có chiều cao.
struct ExploreBannerView: View {
    let items: [ExploreItem]
    let context: ExploreRenderContext

    @State private var selectedId: String = ""

    private static let autoAdvanceNanoseconds: UInt64 = 5_000_000_000

    var body: some View {
        Color(.secondarySystemBackground)
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .overlay {
                TabView(selection: $selectedId) {
                    ForEach(items) { item in
                        Button {
                            context.onSelect(item)
                        } label: {
                            slide(item)
                        }
                        .buttonStyle(.plain)
                        .tag(item.id)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .overlay(alignment: .topTrailing) {
                if items.count > 1 {
                    pageCounter
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 16)
            .task(id: items.map(\.id)) {
                await autoAdvance()
            }
    }

    private func slide(_ item: ExploreItem) -> some View {
        Color(.secondarySystemBackground)
            .overlay {
                RemoteCoverImage(url: item.cover, referer: context.referer(for: item), contentMode: .fill)
            }
            .overlay {
                LinearGradient(
                    colors: [.clear, .black.opacity(0.78)],
                    startPoint: .center,
                    endPoint: .bottom
                )
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 4) {
                    if !item.tag.isEmpty {
                        CoverTagBadge(tag: context.display(item.tag), inset: 0)
                    }
                    // Banner chỉ có ảnh (parser giữ item không tên) ⇒ không vẽ dòng tên rỗng.
                    if !item.name.isEmpty {
                        Text(context.display(item.name))
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(2)
                    }
                    if !item.description.isEmpty {
                        Text(context.display(item.description.cleanHTML()))
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                            .lineLimit(1)
                    }
                }
                .padding(12)
            }
            .clipped()
            .contentShape(Rectangle())
    }

    private var pageCounter: some View {
        let index = (items.firstIndex(where: { $0.id == selectedId }) ?? 0) + 1
        return Text("\(index)/\(items.count)")
            .font(.system(size: 11, weight: .semibold))
            .monospacedDigit()
            .foregroundColor(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color.black.opacity(0.5), in: Capsule())
            .padding(8)
    }

    /// Tự chuyển trang theo vòng. Task gắn với vòng đời view: rời màn hình là huỷ, danh sách đổi là chạy lại.
    @MainActor
    private func autoAdvance() async {
        guard let first = items.first else { return }
        if !items.contains(where: { $0.id == selectedId }) {
            selectedId = first.id
        }
        guard items.count > 1 else { return }
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: Self.autoAdvanceNanoseconds)
            guard !Task.isCancelled else { return }
            let current = items.firstIndex(where: { $0.id == selectedId }) ?? 0
            withAnimation(.easeInOut(duration: 0.35)) {
                selectedId = items[(current + 1) % items.count].id
            }
        }
    }
}
