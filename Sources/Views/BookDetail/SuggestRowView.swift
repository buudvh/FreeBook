import SwiftUI

struct SuggestRowView: View {
    let category: CategoryResult
    let localPath: String
    let downloadUrl: String
    let configJson: String
    let extensionPackageId: String
    let sourceName: String
    
    @State private var novels: [SearchNovelResult] = []
    @State private var isLoading = true
    @State private var errorMessage = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                        .padding(.vertical, 20)
                    Spacer()
                }
            } else if !errorMessage.isEmpty {
                HStack {
                    Text("Lỗi tải gợi ý: \(errorMessage)")
                        .font(.caption)
                        .foregroundColor(.red)
                        .lineLimit(2)
                    Spacer()
                    Button(action: {
                        Task {
                            await loadSuggests()
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
            } else if novels.isEmpty {
                Text("Không có gợi ý nào")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 14) {
                        ForEach(novels) { novel in
                            NavigationLink(destination: BookDetailView(
                                bookId: novel.link,
                                extensionPackageId: extensionPackageId,
                                initialDetailUrl: novel.link,
                                sourceName: sourceName,
                                initialHost: novel.host
                            )) {
                                VStack(alignment: .leading, spacing: 6) {
                                    BookCoverView(bookId: novel.link, coverUrl: novel.cover, width: 80, height: 110)
                                        .cornerRadius(6)
                                        .shadow(radius: 1.5)
                                    
                                    Text(TranslateUtils.translateMeta(novel.name))
                                        .font(.caption2)
                                        .fontWeight(.medium)
                                        .foregroundColor(.primary)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                        .frame(height: 30, alignment: .top)
                                }
                                .frame(width: 80)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 4)
                }
            }
        }
        .task {
            await loadSuggests()
        }
    }
    
    private func loadSuggests() async {
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
            
            let filtered = results.filter { !$0.name.isEmpty && !$0.link.isEmpty }
            let unique = filtered.reduce(into: [SearchNovelResult]()) { acc, item in
                if !acc.contains(where: { normalizeLink($0.link) == normalizeLink(item.link) }) {
                    acc.append(item)
                }
            }
            
            await MainActor.run {
                self.novels = unique
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

fileprivate func normalizeLink(_ link: String) -> String {
    var clean = link.trimmingCharacters(in: .whitespacesAndNewlines)
    if clean.hasPrefix("http://") || clean.hasPrefix("https://") {
        if let range = clean.range(of: "://") {
            let afterScheme = clean[range.upperBound...]
            if let slashIndex = afterScheme.firstIndex(of: "/") {
                clean = String(afterScheme[slashIndex...])
            } else {
                clean = "/"
            }
        }
    }
    if !clean.hasPrefix("/") {
        clean = "/" + clean
    }
    return clean
}
