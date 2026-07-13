import SwiftUI

struct CommentSectionView: View {
    let category: CategoryResult
    let localPath: String
    let downloadUrl: String
    let configJson: String
    
    @State private var comments: [SearchNovelResult] = []
    @State private var isLoading = true
    @State private var errorMessage = ""
    
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
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(comments) { comment in
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
            let (results, _) = try await ExtensionManager.shared.executeCustomScript(
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
