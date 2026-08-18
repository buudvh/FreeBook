import SwiftUI

struct SuggestRowView: View {
    let category: CategoryResult
    let localPath: String
    let downloadUrl: String
    let configJson: String
    let extensionPackageId: String
    let sourceName: String
    let isTranslationEnabled: Bool
    
    @State private var novels: [ExtensionItemResult] = []
    @State private var isLoading = true
    @State private var errorMessage = ""
    @State private var selectedDetailRoute: BookDetailRoute? = nil
    
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
                let columns = [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ]
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(novels) { novel in
                        Button {
                            selectedDetailRoute = BookDetailRoute(
                                bookId: novel.link,
                                extensionPackageId: extensionPackageId,
                                detailUrl: novel.link,
                                sourceName: sourceName,
                                host: novel.host
                            )
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                BookCoverView(bookId: novel.link, coverUrl: novel.cover, width: 48, height: 68)
                                    .cornerRadius(6)
                                    .shadow(radius: 1)
                                
                                let displayName = (isTranslationEnabled && TranslateUtils.containsChinese(novel.name)) ? TranslateUtils.translateMeta(novel.name) : novel.name
                                Text(DisplayTextFormatter.titleCase(displayName))
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(.primary)
                                    .lineLimit(3)
                                    .multilineTextAlignment(.leading)
                                
                                Spacer(minLength: 0)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 4)
            }
        }
        .fullScreenCover(item: $selectedDetailRoute) { route in
            NavigationStack {
                BookDetailView(
                    bookId: route.bookId,
                    extensionPackageId: route.extensionPackageId,
                    initialDetailUrl: route.detailUrl,
                    sourceName: route.sourceName,
                    initialHost: route.host
                )
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
            
            let unique = filterAndDeduplicate(results)
            
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
