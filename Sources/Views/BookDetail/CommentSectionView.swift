import SwiftUI

struct CommentSectionView: View {
    let category: CategoryResult
    let localPath: String
    let downloadUrl: String
    let configJson: String
    let extensionPackageId: String
    let sourceName: String
    
    @State private var comments: [SearchNovelResult] = []
    @State private var isLoading = true
    @State private var errorMessage = ""
    @State private var nextPageUrl: String? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                        .padding(.vertical, 20)
                    Spacer()
                }
            } else if !errorMessage.isEmpty {
                HStack {
                    Text("Lỗi tải bình luận: \(errorMessage)")
                        .font(.caption)
                        .foregroundColor(.red)
                        .lineLimit(2)
                    Spacer()
                    Button(action: {
                        Task {
                            await loadComments()
                        }
                    }) {
                        Image(systemName: "arrow.clockwise.circle.fill")
                            .foregroundColor(.blue)
                            .font(.title3)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color.red.opacity(0.05))
                .cornerRadius(8)
            } else if comments.isEmpty {
                Text("Chưa có bình luận nào")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
            } else {
                let displayComments = Array(comments.prefix(3))
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(displayComments) { comment in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                Image(systemName: "person.circle.fill")
                                    .resizable()
                                    .frame(width: 24, height: 24)
                                    .foregroundColor(.secondary.opacity(0.6))
                                
                                Text(TranslateUtils.translateMeta(comment.name))
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.primary)
                                
                                Spacer()
                            }
                            
                            Text(TranslateUtils.translateMeta(comment.description.cleanHTML()))
                                .font(.footnote)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.leading)
                                .padding(.leading, 32)
                        }
                        
                        Divider()
                            .padding(.leading, 32)
                    }
                    
                    if comments.count > 3 || nextPageUrl != nil {
                        NavigationLink(destination: AllCommentsView(
                            category: category,
                            localPath: localPath,
                            downloadUrl: downloadUrl,
                            configJson: configJson
                        )) {
                            HStack {
                                Spacer()
                                Text("Xem tất cả bình luận")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.accentColor)
                                Spacer()
                            }
                            .padding(.vertical, 8)
                            .background(Color.secondary.opacity(0.05))
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
        .task {
            await loadComments()
        }
    }
    
    private func loadComments() async {
        await MainActor.run {
            isLoading = true
            errorMessage = ""
        }
        
        do {
            let (results, nextPage) = try await ExtensionManager.shared.executeCustomScript(
                localPath: localPath,
                downloadUrl: downloadUrl,
                scriptFileName: category.script,
                input: category.input,
                page: 1,
                pageUrl: nil,
                configJson: configJson
            )
            
            await MainActor.run {
                self.comments = results
                self.nextPageUrl = nextPage
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }
}
