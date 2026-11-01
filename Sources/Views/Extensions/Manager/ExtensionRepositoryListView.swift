import SwiftUI

/// Trang con "Danh sách kho", đẩy vào từ ngăn kéo … của tab "Tất cả tiện ích" (1.3.673; trước đó là mục giữa của ô chọn
/// trên tab Kho tiện ích). Thêm / làm mới kho đi qua `ExtensionUpdateCheckCoordinator` — cùng chủ với lượt tự kiểm tra
/// cập nhật nên không chạy trùng; xoá kho đi qua `ExtensionTransactionCoordinator` và bị khoá khi coordinator đang bận.
struct ExtensionRepositoryListView: View {
    private var library: ExtensionLibraryRepository { .shared }
    private var checker: ExtensionUpdateCheckCoordinator { .shared }
    private var repositories: [ExtensionRepositoryRecord] {
        library.repositories.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    @State private var showingAddRepo = false
    @State private var repositoryToDelete: ExtensionRepositoryRecord?
    @State private var showingDeleteRepositoryAlert = false
    @State private var statusMessage = ""
    @State private var errorMessage = ""

    var body: some View {
        List {
            if ExtensionUpdateCheckStatusLine.hasContent || !statusMessage.isEmpty || !errorMessage.isEmpty {
                Section {
                    if ExtensionUpdateCheckStatusLine.hasContent {
                        ExtensionUpdateCheckStatusLine()
                    }
                    if !statusMessage.isEmpty {
                        Text(statusMessage)
                            .font(.caption)
                            .foregroundColor(.white)
                    }
                    if !errorMessage.isEmpty {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            }
            Section(header: Text("Danh sách kho tiện ích")) {
                if repositories.isEmpty {
                    emptyState
                } else {
                    ForEach(repositories) { repo in
                        repositoryRow(repo)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .backPageTitle("Danh sách kho")
        .toolbar { toolbarContent }
        .alert(
            "Xóa kho tiện ích?",
            isPresented: $showingDeleteRepositoryAlert,
            presenting: repositoryToDelete
        ) { repo in
            Button("Hủy", role: .cancel) {
                repositoryToDelete = nil
            }
            Button("Xóa kho", role: .destructive) {
                deleteRepository(repo)
                repositoryToDelete = nil
            }
        } message: { repo in
            Text("Kho \(repo.name) và các tiện ích đã cài từ kho này sẽ bị xóa khỏi ứng dụng.")
        }
        .sheet(isPresented: $showingAddRepo) {
            AddRepositoryView { name, url in
                addRepository { await checker.addRepository(name: name, url: url) }
            }
        }
    }

    // Bên trái là nút back + tiêu đề giữa ⇒ ↻ đứng sát trước + (một `ToolbarItem` cho cả cụm).
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            HStack(spacing: HeaderButtonMetrics.pairSpacing) {
                Button(action: { checker.checkNow() }) {
                    Group {
                        if checker.isChecking {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 17, weight: .semibold))
                        }
                    }
                    .frame(width: HeaderButtonMetrics.pairIconWidth, height: 38)
                }
                .disabled(checker.isBusy || repositories.isEmpty)
                .accessibilityLabel("Làm mới tất cả kho")
                Button(action: { showingAddRepo = true }) {
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: HeaderButtonMetrics.pairIconWidth, height: 38)
                }
                .disabled(checker.isBusy)
                .accessibilityLabel("Thêm kho")
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.stack.3d.up.slash")
                .font(.system(size: 40))
                .foregroundColor(.gray)
            Text("Bạn có thể nhập link kho tiện ích (định dạng plugin.json) để bắt đầu tải các nguồn bóc tách truyện.")
                .font(.subheadline)
                .foregroundColor(.gray)
            Button(action: { addRepository { await checker.addDefaultRepository() } }) {
                Text("Nhập kho tiện ích mặc định (buudvh)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.18))
                    .overlay(Capsule().stroke(Color.white.opacity(0.35), lineWidth: 1))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(checker.isBusy)
            .padding(.top, 5)
        }
        .padding(.vertical)
    }

    private func repositoryRow(_ repo: ExtensionRepositoryRecord) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(repo.name)
                    .font(.headline)
                Text(repo.url)
                    .font(.caption)
                    .foregroundColor(.gray)
                    .lineLimit(1)
            }
            Spacer()

            Button {
                guard !checker.isBusy else { return }
                repositoryToDelete = repo
                showingDeleteRepositoryAlert = true
            } label: {
                Image(systemName: "trash")
                    .foregroundColor(.red)
                    .padding(8)
                    .background(Color.red.opacity(0.1))
                    .clipShape(Circle())
            }
            .buttonStyle(.borderless)
            .disabled(checker.isBusy)
            .accessibilityLabel("Xóa kho \(repo.name)")
        }
    }

    // MARK: - Thao tác

    private func addRepository(_ add: @escaping @MainActor () async -> String) {
        errorMessage = ""
        Task {
            let message = await add()
            if !message.isEmpty { statusMessage = message }
        }
    }

    private func deleteRepository(_ repo: ExtensionRepositoryRecord) {
        guard !checker.isBusy else {
            statusMessage = "Hãy chờ cập nhật kho hoàn tất trước khi xóa."
            return
        }

        if (TTSManager.shared.isPlaying || TTSManager.shared.showFloatingWidget),
           let playingPackageId = TTSManager.shared.extensionInfo?.packageId,
           library.installed.contains(where: { $0.packageId == playingPackageId && $0.repositoryUrl == repo.url }) {
            statusMessage = "Không thể xóa kho đang được TTS sử dụng. Hãy dừng TTS trước."
            return
        }

        // Coordinator gỡ file + bản ghi + localStorage của các tiện ích thuộc kho, rồi xoá kho và cache registry.
        switch ExtensionTransactionCoordinator.shared.deleteRepository(url: repo.url) {
        case .success:
            statusMessage = "Đã xóa kho tiện ích."
        case .failure(let err):
            errorMessage = "Xóa kho thất bại: \(err.localizedDescription)"
        }
    }
}
