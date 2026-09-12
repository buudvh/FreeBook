import SwiftUI

struct BookCoverView: View {
    let bookId: String
    let coverUrl: String
    let width: CGFloat
    let height: CGFloat
    
    @State private var localImage: UIImage? = nil
    
    var body: some View {
        Group {
            if let uiImage = localImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                AsyncImage(url: URL(string: coverUrl)) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .onAppear {
                                triggerSaveLocalCover()
                            }
                    case .failure:
                        fallbackPlaceholder
                    case .empty:
                        fallbackPlaceholder
                    @unknown default:
                        fallbackPlaceholder
                    }
                }
            }
        }
        .frame(width: width, height: height)
        .clipped()
        .onAppear {
            loadLocalImage()
        }
        .onChange(of: bookId) { _, _ in
            loadLocalImage()
        }
    }
    
    private var fallbackPlaceholder: some View {
        ZStack {
            Color.gray.opacity(0.15)
            Image(systemName: "book.closed")
                .foregroundColor(.secondary.opacity(0.5))
                .font(.system(size: min(width, height) * 0.35))
        }
        .frame(width: width, height: height)
    }
    
    private func loadLocalImage() {
        if let image = ImageCacheManager.shared.loadLocalCover(for: bookId) {
            self.localImage = image
        } else {
            self.localImage = nil
            // Nếu chưa có local, có thể tải ngầm luôn nếu có URL hợp lệ
            if !coverUrl.isEmpty {
                triggerSaveLocalCover()
            }
        }
    }
    
    private func triggerSaveLocalCover() {
        guard !coverUrl.isEmpty else { return }
        ImageCacheManager.shared.downloadAndSaveCover(urlStr: coverUrl, bookId: bookId) { image in
            if let image = image {
                DispatchQueue.main.async {
                    self.localImage = image
                }
            }
        }
    }
}
