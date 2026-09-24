import SwiftUI
import SwiftData

/// Màn hình quản lý cấu hình bật/tắt dịch riêng biệt theo từng Nguồn và Truyện.
public struct TranslationScopeManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var allBooks: [Book]
    @Query private var allExtensions: [Extension]

    @State private var bookOverrides: [String: TranslationConfigStore.OverrideMode] = [:]
    @State private var sourceOverrides: [String: TranslationConfigStore.OverrideMode] = [:]
    @State private var showingResetAlert = false

    public init() {}

    private var bookIds: [String] {
        bookOverrides.keys.sorted()
    }

    private var sourcePackageIds: [String] {
        sourceOverrides.keys.sorted()
    }

    public var body: some View {
        List {
            // Phần 1: Cấu hình theo Nguồn truyện
            Section {
                if sourcePackageIds.isEmpty {
                    Text("Chưa có nguồn truyện nào đặt cấu hình riêng")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(sourcePackageIds, id: \.self) { packageId in
                        sourceRow(for: packageId)
                    }
                    .onDelete(perform: deleteSources)
                }
            } header: {
                Text("Cấu hình theo Nguồn truyện (\(sourcePackageIds.count))")
            } footer: {
                Text("Các nguồn ở trên sẽ ghi đè thiết lập toàn cục khi đọc hoặc nghe TTS.")
            }

            // Phần 2: Cấu hình theo Từng truyện
            Section {
                if bookIds.isEmpty {
                    Text("Chưa có truyện nào đặt cấu hình riêng")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(bookIds, id: \.self) { bookId in
                        bookRow(for: bookId)
                    }
                    .onDelete(perform: deleteBooks)
                }
            } header: {
                Text("Cấu hình theo Truyện (\(bookIds.count))")
            } footer: {
                Text("Cấu hình theo truyện có độ ưu tiên cao nhất, ghi đè cả nguồn và toàn cục.")
            }

            // Phần 3: Thao tác đặt lại
            if !sourcePackageIds.isEmpty || !bookIds.isEmpty {
                Section {
                    Button(role: .destructive) {
                        showingResetAlert = true
                    } label: {
                        HStack {
                            Spacer()
                            Text("Đặt lại tất cả về mặc định")
                                .fontWeight(.medium)
                            Spacer()
                        }
                    }
                } footer: {
                    Text("Xoá toàn bộ cấu hình riêng của nguồn và truyện, tất cả sẽ tuân theo thiết lập toàn cục.")
                }
            }
        }
        .navigationTitle("Cấu hình Dịch riêng biệt")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !sourcePackageIds.isEmpty || !bookIds.isEmpty {
                ToolbarItem(placement: .navigationBarTrailing) {
                    EditButton()
                }
            }
        }
        .onAppear {
            reloadOverrides()
        }
        .onReceive(NotificationCenter.default.publisher(for: TranslationConfigStore.didChangeNotification)) { _ in
            reloadOverrides()
        }
        .alert("Đặt lại cấu hình?", isPresented: $showingResetAlert) {
            Button("Huỷ", role: .cancel) {}
            Button("Đặt lại", role: .destructive) {
                TranslationConfigStore.shared.resetAllOverrides()
                reloadOverrides()
            }
        } message: {
            Text("Bạn có chắc chắn muốn xoá tất cả cấu hình dịch riêng cho từng nguồn và truyện?")
        }
    }

    // MARK: - Row Views

    @ViewBuilder
    private func sourceRow(for packageId: String) -> some View {
        let name = resolvedSourceName(for: packageId)
        let mode = sourceOverrides[packageId] ?? .inherited

        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .font(.body)
                Text(packageId == "local" ? "Sách tự nhập" : packageId)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Menu {
                Button {
                    TranslationConfigStore.shared.setSourceOverride(packageId: packageId, mode: .enabled)
                } label: {
                    Label("Luôn Bật dịch", systemImage: mode == .enabled ? "checkmark" : "")
                }

                Button {
                    TranslationConfigStore.shared.setSourceOverride(packageId: packageId, mode: .disabled)
                } label: {
                    Label("Luôn Tắt dịch", systemImage: mode == .disabled ? "checkmark" : "")
                }

                Divider()

                Button(role: .destructive) {
                    TranslationConfigStore.shared.setSourceOverride(packageId: packageId, mode: .inherited)
                } label: {
                    Label("Xoá cấu hình riêng (Mặc định)", systemImage: "trash")
                }
            } label: {
                badgeView(mode: mode)
            }
        }
    }

    @ViewBuilder
    private func bookRow(for bookId: String) -> some View {
        let title = resolvedBookTitle(for: bookId)
        let mode = bookOverrides[bookId] ?? .inherited

        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body)
                    .lineLimit(1)
                Text("ID: \(bookId)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Menu {
                Button {
                    TranslationConfigStore.shared.setBookOverride(bookId: bookId, mode: .enabled)
                } label: {
                    Label("Luôn Bật dịch", systemImage: mode == .enabled ? "checkmark" : "")
                }

                Button {
                    TranslationConfigStore.shared.setBookOverride(bookId: bookId, mode: .disabled)
                } label: {
                    Label("Luôn Tắt dịch", systemImage: mode == .disabled ? "checkmark" : "")
                }

                Divider()

                Button(role: .destructive) {
                    TranslationConfigStore.shared.setBookOverride(bookId: bookId, mode: .inherited)
                } label: {
                    Label("Xoá cấu hình riêng (Theo nguồn)", systemImage: "trash")
                }
            } label: {
                badgeView(mode: mode)
            }
        }
    }

    @ViewBuilder
    private func badgeView(mode: TranslationConfigStore.OverrideMode) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(mode == .enabled ? Color.green : Color.red)
                .frame(width: 8, height: 8)
            Text(mode == .enabled ? "Bật" : "Tắt")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(mode == .enabled ? .green : .red)
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(UIColor.secondarySystemFill), in: RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Actions & Helpers

    private func deleteSources(at offsets: IndexSet) {
        for index in offsets {
            let pkgId = sourcePackageIds[index]
            TranslationConfigStore.shared.setSourceOverride(packageId: pkgId, mode: .inherited)
        }
    }

    private func deleteBooks(at offsets: IndexSet) {
        for index in offsets {
            let bId = bookIds[index]
            TranslationConfigStore.shared.setBookOverride(bookId: bId, mode: .inherited)
        }
    }

    private func reloadOverrides() {
        bookOverrides = TranslationConfigStore.shared.allBookOverrides
        sourceOverrides = TranslationConfigStore.shared.allSourceOverrides
    }

    private func resolvedSourceName(for packageId: String) -> String {
        if packageId == "local" || packageId.isEmpty {
            return "Sách tự nhập (Local)"
        }
        if let found = allExtensions.first(where: { $0.packageId == packageId }) {
            return found.name
        }
        return packageId
    }

    private func resolvedBookTitle(for bookId: String) -> String {
        if let found = allBooks.first(where: { $0.bookId == bookId }) {
            return found.title
        }
        return "Truyện (\(bookId))"
    }
}
