import SwiftUI

/// Hỏi lại người dùng trước khi ghi: tóm tắt `manifest.json` của file sao lưu, cho chọn nhóm
/// muốn gộp vào và có ghi đè từ điển chung hay không.
struct RestoreOptionsSheet: View {
    let sourceName: String
    let manifest: BackupManifest
    /// TTS đang phát thì chặn — restore ghi vào đúng những hàng mà TTS đang sở hữu tiến độ.
    let isTTSPlaying: Bool
    let onConfirm: (BackupRestoreWorker.Options) -> Void
    let onCancel: () -> Void

    @State private var scopes: Set<BackupScope>
    @State private var overwriteShared = false

    init(
        sourceName: String,
        manifest: BackupManifest,
        isTTSPlaying: Bool,
        onConfirm: @escaping (BackupRestoreWorker.Options) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.sourceName = sourceName
        self.manifest = manifest
        self.isTTSPlaying = isTTSPlaying
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        _scopes = State(initialValue: Set(manifest.availableScopes))
    }

    var body: some View {
        NavigationView {
            List {
                summarySection

                BackupScopeToggleList(
                    selection: $scopes,
                    header: "Nhóm sẽ khôi phục",
                    availableScopes: manifest.availableScopes,
                    showsEstimatedSize: false
                )

                Section(footer: Text("Từ điển chung chỉ được cài khi máy còn thiếu. Bật tuỳ chọn này nếu muốn lấy bản trong file sao lưu thay cho bản đang có.")) {
                    Toggle("Ghi đè từ điển chung", isOn: $overwriteShared)
                        .disabled(!manifest.availableScopes.contains(.dictShared))
                }

                if isTTSPlaying {
                    Section {
                        Label("Hãy dừng phát TTS trước khi khôi phục", systemImage: "exclamationmark.triangle")
                            .foregroundColor(.orange)
                            .font(.subheadline)
                    }
                }
            }
            .navigationTitle("Khôi phục")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Huỷ", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Khôi phục") {
                        onConfirm(BackupRestoreWorker.Options(
                            scopes: scopes,
                            overwriteSharedDictionaries: overwriteShared
                        ))
                    }
                    .disabled(isTTSPlaying)
                }
            }
        }
    }

    private var summarySection: some View {
        Section(header: Text("File sao lưu")) {
            infoRow("Tên file", sourceName)
            infoRow("Tạo lúc", Self.dateText(manifest.createdAt))
            infoRow("Phiên bản app", manifest.appVersion)
            infoRow("Truyện", "\(manifest.counts.books)")
            infoRow("Chương", "\(manifest.counts.chapters) (\(manifest.counts.cachedChapters) đã tải)")
            if manifest.counts.covers > 0 {
                infoRow("Ảnh bìa truyện nhập", "\(manifest.counts.covers)")
            }
            infoRow("Kho / Extension", "\(manifest.counts.repositories) / \(manifest.counts.extensions)")
            infoRow(
                "File từ điển",
                "\(manifest.counts.customDictionaries + manifest.counts.bookDictionaries + manifest.counts.sharedDictionaries)"
            )
        }
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
            Spacer()
            Text(value)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }

    private static func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
